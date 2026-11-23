include { BUILD_PARTITIONING_TOOLS } from '../subworkflows/build_partitioning_tools.nf'
include { PARTITION_WITH_REGION_FILTER } from '../subworkflows/partition_with_region_filter.nf'
include { RENDER_GRAPH_REPORTS } from '../subworkflows/render_graph_reports.nf'
include { APPEND_TO_ROWS } from '../modules/append_to_rows.nf'
include { INDEX_ROWS } from '../modules/index_rows.nf'

params {
    repository: String = "${params.repository_dir}/mt-kahypar"
    build_threads: Integer
    region_filter_revision: String
    mt_kahypar_revision: String
    graph_dir: String
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
    // One filter per graph; each policy reuses that graph's natural edges.
    def filters = graphs.map { graph -> tuple(graph.baseName, graph, filterOpts) }
    def partitions = filters.map { graphId, _graph, _opts -> graphId }
        .combine(ratingOpts)
        .map { graphId, rating ->
            def key = [graphId: graphId, policy: rating.c_rating_edge_metadata]
            tuple(key, graphId, sharedKahyparOpts + rating)
        }
    def filterTools = BUILD_PARTITIONING_TOOLS.out.region_filter
    def partitionTools = BUILD_PARTITIONING_TOOLS.out.mt_kahypar
    PARTITION_WITH_REGION_FILTER(
        filters, partitions,
        filterTools.map { _commit, executable -> executable },
        partitionTools.map { _commit, executable -> executable }
    )

    def naturalEdges = PARTITION_WITH_REGION_FILTER.out.natural_edges

    // Render each partition with the natural edges from its RegionFilter run
    def reportGraphs = filters.map { graphId, graph, _opts ->
        def xyz = graph.resolveSibling("${graph.baseName}.xyz")
        def coords = xyz.exists() ? xyz : file("${xyz}.bz2", checkIfExists: true)
        tuple(graphId, graph, coords)
    }

    APPEND_TO_ROWS(naturalEdges, 0)
    def edgeMarks = APPEND_TO_ROWS.out.output.map { key, marks ->
        tuple(key, 'natural_edges', marks)
    }
    INDEX_ROWS(PARTITION_WITH_REGION_FILTER.out.partitions, 1)
    def nodeMarks = INDEX_ROWS.out.output.map { key, marks ->
        tuple(key.graphId, key.policy, marks)
    }
    def reportSpecs = ratingOpts.map { opts ->
        def policy = opts.c_rating_edge_metadata
        tuple(policy, policy, 'natural_edges')
    }
    RENDER_GRAPH_REPORTS(reportGraphs, nodeMarks, edgeMarks, reportSpecs, [coord_format: 'dimacs10-osm'])

    // Publish only the graph and policy identifiers alongside the output files.
    def partitionFiles = PARTITION_WITH_REGION_FILTER.out.partitions.mix(
        PARTITION_WITH_REGION_FILTER.out.partition_logs,
        PARTITION_WITH_REGION_FILTER.out.results
    ).map { key, artifact -> tuple(key.graphId, key.policy, artifact) }

    // Publish results
    publish:
    region_log = PARTITION_WITH_REGION_FILTER.out.filter_logs
    natural_edges = naturalEdges
    kahypar_results = partitionFiles
    partition_maps = RENDER_GRAPH_REPORTS.out.reports
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
