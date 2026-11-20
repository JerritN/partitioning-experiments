include { BUILD_PARTITIONING_TOOLS } from '../subworkflows/build_partitioning_tools.nf'
include { PARTITION_WITH_REGION_FILTER } from '../subworkflows/partition_with_region_filter.nf'
include { RENDER_GRAPH_REPORTS } from '../subworkflows/render_graph_reports.nf'
include { APPEND_TO_ROWS } from '../modules/append_to_rows.nf'
include { INDEX_ROWS } from '../modules/index_rows.nf'

params {
    repository: String = "${params.project_path}/mt-kahypar"
    build_threads: Integer
    region_filter_revision: String
    mt_kahypar_revision: String
    graph_dir: String = "${params.project_path}/data"
    region_filter_k: Integer = 8
    mt_kahypar_threads: Integer = 8
    mt_kahypar_blocks: Integer = 8
    mt_kahypar_epsilon: Float = 0.03f
    mt_kahypar_objective: String = "cut"
    mt_kahypar_preset: String = "default"
}

workflow {
    main:
    BUILD_PARTITIONING_TOOLS(params.repository, params.build_threads, [
        region_filter: params.region_filter + [revision: params.region_filter_revision],
        mt_kahypar: params.mt_kahypar + [revision: params.mt_kahypar_revision]
    ])

    // Load graph files
    def graphPath = file(params.graph_dir, checkIfExists: true)
    def graphs = channel.fromPath(
        graphPath.isDirectory() ? "${graphPath}/*.graph" : graphPath,
        checkIfExists: true
    )

    def filterOpts = [k: params.region_filter_k]
    def sharedKahyparOpts = [
        file_format: 'metis',
        edge_metadata_type: 'natural_edge',
        threads: params.mt_kahypar_threads,
        blocks: params.mt_kahypar_blocks,
        epsilon: params.mt_kahypar_epsilon,
        objective: params.mt_kahypar_objective,
        preset_type: params.mt_kahypar_preset,
    ]
    def ratingOpts = channel.fromList([
        [c_rating_edge_metadata: 'ignore'],
        [c_rating_edge_metadata: 'skip_natural_edge'],
        [c_rating_edge_metadata: 'natural_edge_contribute_zero'],
        [c_rating_edge_metadata: 'natural_edge_contribute_negative'],
    ])
    def runs = graphs.combine(ratingOpts).map { graph, rating ->
        tuple([graph: graph.baseName], graph, filterOpts, sharedKahyparOpts + rating)
    }
    PARTITION_WITH_REGION_FILTER(runs, BUILD_PARTITIONING_TOOLS.out.region_filter, BUILD_PARTITIONING_TOOLS.out.mt_kahypar)
    def naturalEdges = PARTITION_WITH_REGION_FILTER.out.natural_edges

    // Render each partition with the natural edges from its RegionFilter run
    def reportGraphs = naturalEdges.map { key, _edges ->
        def graph = key.graphFile
        def xyz = graph.resolveSibling("${graph.baseName}.xyz")
        def coords = xyz.exists() ? xyz : file("${xyz}.bz2", checkIfExists: true)
        tuple(key, graph, coords)
    }

    APPEND_TO_ROWS(naturalEdges, 0)
    def edgeMarks = APPEND_TO_ROWS.out.output.map { context, marks ->
        tuple(context, 'natural_edges', marks)
    }
    INDEX_ROWS(PARTITION_WITH_REGION_FILTER.out.partitions, 1)
    def nodeMarks = INDEX_ROWS.out.output.map { context, marks ->
        tuple(context.filterKey, context.kahyparOpts.c_rating_edge_metadata, marks)
    }
    def reportSpecs = ratingOpts.map { opts ->
        def policy = opts.c_rating_edge_metadata
        tuple(policy, policy, 'natural_edges')
    }
    RENDER_GRAPH_REPORTS(reportGraphs, nodeMarks, edgeMarks, reportSpecs, [coord_format: 'dimacs10-osm'])

    // Publish only the graph and policy identifiers alongside the output files.
    def filterLogs = PARTITION_WITH_REGION_FILTER.out.filter_logs.map { key, log -> tuple(key.graph, log) }
    def edgeFiles = naturalEdges.map { key, edges -> tuple(key.graph, edges) }
    def partitionFiles = PARTITION_WITH_REGION_FILTER.out.partitions.mix(
        PARTITION_WITH_REGION_FILTER.out.partition_logs,
        PARTITION_WITH_REGION_FILTER.out.results
    ).map { context, artifact -> tuple(context.graph, context.kahyparOpts.c_rating_edge_metadata, artifact) }
    def maps = RENDER_GRAPH_REPORTS.out.reports.map { context, report ->
        tuple(context.graph.graph, context.report, report)
    }

    // Publish results
    publish:
    region_log = filterLogs
    natural_edges = edgeFiles
    kahypar_results = partitionFiles
    partition_maps = maps
}

output {
    region_log {
        mode 'copy'
        path { graph, file ->
            file >> "${graph}/region_filter.log"
        }
    }

    natural_edges {
        mode 'copy'
        path { graph, file ->
            file >> "${graph}/natural_edges_metadata.txt"
        }
    }

    partition_maps {
        mode 'copy'
        path { graph, policy, file ->
            file >> "${graph}/${policy}/${file.name}"
        }
    }

    kahypar_results {
        mode 'copy'
        path { graph, policy, file ->
            file >> "${graph}/${policy}/${file.name}"
        }
    }
}
