include { BUILD_CMAKE_FROM_GIT } from '../subworkflows/build_cmake_from_git.nf'
include { RENDER_GRAPH_REPORTS } from '../subworkflows/render_graph_reports.nf'
include { REGION_ROUND_MARKS } from '../modules/region_round_marks.nf'
include { REGION_FILTER } from '../modules/region_filter.nf'
include { TAKE_COLUMNS } from '../modules/take_columns.nf'
include { MT_KAHYPAR } from '../modules/mt_kahypar.nf'
include { APPEND_TO_ROWS } from '../modules/append_to_rows.nf'
include { INDEX_ROWS } from '../modules/index_rows.nf'

params {
    // Use with -resume; set a stage to false to rerun its tasks.
    cache_git_checkout: Boolean = true
    cache_cmake_build: Boolean = true
    cache_region_filter: Boolean = true
    cache_mt_kahypar: Boolean = true
    cache_streetviz: Boolean = true

    repository: String = "${params.project_path}/mt-kahypar"
    kahypar_commit: String = "085bdae"
    region_filter_commit: String = "7467201"
    build_threads: Integer = 8
    graph_dir: String = "${params.project_path}/data"
    region_filter_u: Integer = 1000
    region_filter_rounds: Integer = 1
    mt_kahypar_threads: Integer = 8
    mt_kahypar_blocks: Integer = 8
    mt_kahypar_epsilon: Float = 0.03f
    mt_kahypar_objective: String = "cut"
    mt_kahypar_preset_type: String = "default"
}

workflow {
    main:
    assert params.region_filter_rounds in 1..31 : 'region_filter_rounds must be between 1 and 31 for per-round edge masks'

    // Build the two tools at their requested revisions.
    def kahyparBuildOpts = [
        preset: 'minimal',
        definitions: [
            KAHYPAR_ENABLE_GRAPH_PARTITIONING_FEATURES: true
        ],
        target: 'MtKaHyPar',
        binary: params.mt_kahypar.mt_kahypar_binary,
        threads: params.build_threads
    ]
    def regionFilterBuildOpts = [
        preset: 'minimal',
        target: 'RegionFilter',
        binary: params.mt_kahypar.region_filter_binary,
        threads: params.build_threads
    ]
    def buildRequests = channel.of(
        tuple([tool: 'kahypar'], params.repository, params.kahypar_commit, kahyparBuildOpts),
        tuple([tool: 'regionFilter'], params.repository, params.region_filter_commit, regionFilterBuildOpts)
    )
    BUILD_CMAKE_FROM_GIT(buildRequests)
    def binaries = BUILD_CMAKE_FROM_GIT.out.binary.branch { context, _binary ->
        kahypar: context.tool == 'kahypar'
        regionFilter: context.tool == 'regionFilter'
    }
    def kahyparExecutable = binaries.kahypar
        .map { _context, binary -> binary }
    def regionFilterExecutable = binaries.regionFilter
        .map { _context, binary -> binary }

    // Load graph files
    def graphPath = file(params.graph_dir, checkIfExists: true)
    def graphs = channel.fromPath(
        graphPath.isDirectory() ? "${graphPath}/*.graph" : graphPath,
        checkIfExists: true
    ).map { graph ->
        tuple([graph: graph.baseName, graphFile: graph], graph)
    }
        
    // Run RegionFilter on each graph file
    def regionFilterOpts = channel.value([
        U: params.region_filter_u,
        rounds: params.region_filter_rounds
    ])
    
    def regionFilterInputs = graphs
        .combine(regionFilterExecutable)
        .combine(regionFilterOpts)
        .map { context, graph, executable, opts ->
            tuple(context + [regionFilterOpts: opts], executable, graph, opts)
        }

    REGION_FILTER(regionFilterInputs)
    def cutEdges = REGION_FILTER.out.cut_edges

    // convert the cut edges to a format suitable for Mt-KaHyPar
    TAKE_COLUMNS(cutEdges, [1, 2])
    def naturalEdges = TAKE_COLUMNS.out.output

    // Run Mt-KaHyPar on the natural edges
    def sharedKahyparOpts = [
        file_format: 'metis',
        edge_metadata_type: 'natural_edge',
        threads: params.mt_kahypar_threads,
        blocks: params.mt_kahypar_blocks,
        epsilon: params.mt_kahypar_epsilon,
        objective: params.mt_kahypar_objective,
        preset_type: params.mt_kahypar_preset_type,
    ]
    def ratingOpts = channel.fromList([
        [c_rating_edge_metadata: 'ignore'],
        [c_rating_edge_metadata: 'skip_natural_edge'],
        [c_rating_edge_metadata: 'natural_edge_contribute_zero'],
        [c_rating_edge_metadata: 'natural_edge_contribute_negative'],
    ])
    def kahyparOpts = ratingOpts.map { ratingOpt ->
        sharedKahyparOpts + ratingOpt
    }
    def kahyparInputs = naturalEdges
        .combine(kahyparExecutable)
        .combine(kahyparOpts)
        .map { context, metadata, executable, opts ->
            tuple(
                context + [kahyparOpts: opts],
                executable,
                context.graphFile,
                [],
                metadata,
                opts
            )
        }
    
    MT_KAHYPAR(kahyparInputs)

    // Share graph coordinates across partition and RegionFilter round reports.
    def reportGraphs = graphs.map { context, graph ->
        def xyz = graph.resolveSibling("${graph.baseName}.xyz")
        def coords = xyz.exists() ? xyz : file("${xyz}.bz2", checkIfExists: true)
        tuple(context.graph, graph, coords)
    }

    APPEND_TO_ROWS(naturalEdges, 0)
    def edgeMarks = APPEND_TO_ROWS.out.output.map { context, marks ->
        tuple(context.graph, 'natural_edges', marks)
    }
    INDEX_ROWS(MT_KAHYPAR.out.partition, 1)
    def nodeMarks = INDEX_ROWS.out.output.map { context, marks ->
        tuple(context.graph, context.kahyparOpts.c_rating_edge_metadata, marks)
    }
    def reportSpecs = ratingOpts.map { opts ->
        def policy = opts.c_rating_edge_metadata
        tuple(policy, policy, 'natural_edges')
    }
    // Region IDs occupy one column per round; the cut-edge mask uses the corresponding bit.
    def rounds = channel.fromList((0..<params.region_filter_rounds).toList())
    def roundInputs = REGION_FILTER.out.regions
        .join(cutEdges, failOnDuplicate: true, failOnMismatch: true)
        .combine(rounds)
        .map { context, regions, cuts, round -> tuple(context, round, regions, cuts) }
    REGION_ROUND_MARKS(roundInputs)
    def roundNodeMarks = REGION_ROUND_MARKS.out.marks.map { context, round, edges, nodes ->
        tuple(context.graph, round, nodes)
    }
    def roundEdgeMarks = REGION_ROUND_MARKS.out.marks.map { context, round, edges, nodes ->
        tuple(context.graph, round, edges)
    }
    def roundSpecs = rounds.map { round -> tuple("region_filter/round-${round}", round, round) }

    RENDER_GRAPH_REPORTS(
        reportGraphs,
        nodeMarks.mix(roundNodeMarks),
        edgeMarks.mix(roundEdgeMarks),
        reportSpecs.mix(roundSpecs),
        [coord_format: 'dimacs10-osm']
    )

    // Publish results
    publish:
    region_log = REGION_FILTER.out.log
    natural_edges = naturalEdges
    kahypar_results = MT_KAHYPAR.out.partition.mix(
        MT_KAHYPAR.out.log
    )
    graph_maps = RENDER_GRAPH_REPORTS.out.reports
}

output {
    region_log {
        mode 'copy'
        path { context, file ->
            file >> "${context.graph}/region_filter.log"
        }
    }

    natural_edges {
        mode 'copy'
        path { context, file ->
            file >> "${context.graph}/natural_edges_metadata.txt"
        }
    }

    graph_maps {
        mode 'copy'
        path { context, file ->
            file >> "${context.graph}/${context.report}/${file.name}"
        }
    }

    kahypar_results {
        mode 'copy'
        path { context, file ->
            file >> "${context.graph}/${context.kahyparOpts.c_rating_edge_metadata}/${file.name}"
        }
    }
}
