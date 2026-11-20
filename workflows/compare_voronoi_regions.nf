include { BUILD_CMAKE_FROM_GIT } from '../subworkflows/build_cmake_from_git.nf'
include { RENDER_GRAPH_REPORTS } from '../subworkflows/render_graph_reports.nf'
include { REGION_ROUND_MARKS } from '../modules/region_round_marks.nf'
include { REGION_FILTER } from '../modules/region_filter.nf'

params {
    // Use with -resume; set a stage to false to rerun its tasks.
    cache_git_checkout: Boolean = true
    cache_cmake_build: Boolean = true
    cache_region_filter: Boolean = true
    cache_streetviz: Boolean = true

    repository: String = "${params.project_path}/mt-kahypar"
    region_filter_commit: String = "7467201"
    build_threads: Integer = 8
    graph_dir: String = "${params.project_path}/data"
    region_filter_u: Integer = 1000
    region_filter_rounds: Integer = 1
}

workflow {
    main:
    assert params.region_filter_rounds in 1..31 : 'region_filter_rounds must be between 1 and 31 for per-round edge masks'

    def regionFilterBuildOpts = [
        preset: 'minimal',
        target: 'RegionFilter',
        binary: params.mt_kahypar.region_filter_binary,
        threads: params.build_threads
    ]
    def buildRequests = channel.of(
        tuple([tool: 'regionFilter'], params.repository, params.region_filter_commit, regionFilterBuildOpts)
    )
    BUILD_CMAKE_FROM_GIT(buildRequests)
    def regionFilterExecutable = BUILD_CMAKE_FROM_GIT.out.binary.map { _context, binary -> binary }

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

    def reportGraphs = graphs.map { context, graph ->
        def xyz = graph.resolveSibling("${graph.baseName}.xyz")
        def coords = xyz.exists() ? xyz : file("${xyz}.bz2", checkIfExists: true)
        tuple(context.graph, graph, coords)
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
    def roundSpecs = rounds.map { round -> tuple("round-${round}", round, round) }

    RENDER_GRAPH_REPORTS(
        reportGraphs,
        roundNodeMarks,
        roundEdgeMarks,
        roundSpecs,
        [coord_format: 'dimacs10-osm']
    )

    // Publish results
    publish:
    region_log = REGION_FILTER.out.log
    graph_maps = RENDER_GRAPH_REPORTS.out.reports
}

output {
    region_log {
        mode 'copy'
        path { context, file ->
            file >> "${context.graph}/region_filter/region_filter.log"
        }
    }

    graph_maps {
        mode 'copy'
        path { context, file ->
            file >> "${context.graph}/region_filter/${context.report}/${file.name}"
        }
    }
}
