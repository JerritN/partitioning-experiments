include { BUILD_CMAKE_FROM_GIT } from '../subworkflows/build_cmake_from_git.nf'
include { RENDER_GRAPH_REPORTS } from '../subworkflows/render_graph_reports.nf'
include { SPLIT_COLUMNS } from '../modules/split_columns.nf'
include { INDEX_ROWS } from '../modules/index_rows.nf'
include { FILTER_ROWS_BY_BIT } from '../modules/filter_rows_by_bit.nf'
include { TAKE_COLUMNS } from '../modules/take_columns.nf'
include { APPEND_TO_ROWS } from '../modules/append_to_rows.nf'
include { REGION_FILTER } from '../modules/region_filter.nf'

params {
    repository: String = "${params.repository_dir}/mt-kahypar"
    build_threads: Integer
    region_filter_revision: String
    graph_dir: String
    region_filter_u: Integer = 1000
    region_filter_rounds: Integer = 1
}

workflow {
    main:
    assert params.region_filter_rounds in 1..31 : 'region_filter_rounds must be between 1 and 31 for per-round edge masks'

    def regionFilterBuildOpts = [
        preset: params.region_filter.cmake_preset,
        target: params.region_filter.target,
        binary: params.region_filter.binary,
        threads: params.build_threads
    ]
    def buildRequests = channel.of(
        tuple('regionFilter', params.repository, params.region_filter_revision, regionFilterBuildOpts)
    )
    BUILD_CMAKE_FROM_GIT(buildRequests)
    def regionFilterExecutable = BUILD_CMAKE_FROM_GIT.out.binary.map { _key, _commit, binary -> binary }

    // Load graph files
    def graphPath = file(params.graph_dir, checkIfExists: true)
    def graphs = channel.fromPath(
        graphPath.isDirectory() ? "${graphPath}/*.graph" : graphPath,
        checkIfExists: true
    ).map { graph ->
        tuple(graph.baseName, graph)
    }

    // Run RegionFilter on each graph file
    def regionFilterOpts = channel.value([
        U: params.region_filter_u,
        rounds: params.region_filter_rounds
    ])

    def regionFilterInputs = graphs
        .combine(regionFilterExecutable)
        .combine(regionFilterOpts)
        .map { graphId, graph, executable, opts ->
            tuple(graphId, executable, graph, opts)
        }

    REGION_FILTER(regionFilterInputs)
    def cutEdges = REGION_FILTER.out.cut_edges

    def reportGraphs = graphs.map { graphId, graph ->
        def xyz = graph.resolveSibling("${graph.baseName}.xyz")
        def coords = xyz.exists() ? xyz : file("${xyz}.bz2", checkIfExists: true)
        tuple(graphId, graph, coords)
    }

    // Column 1 holds the Voronoi cells for round 0.
    SPLIT_COLUMNS(REGION_FILTER.out.regions)
    def cells = SPLIT_COLUMNS.out.columns.flatMap { graphId, columns ->
        assert columns.size() == params.region_filter_rounds : "Unexpected region column count for ${graphId}"
        columns.collect { column ->
            tuple([graphId: graphId, round: column.baseName.toInteger() - 1], column)
        }
    }
    INDEX_ROWS(cells, 1)
    def roundNodeMarks = INDEX_ROWS.out.output.map { roundKey, marks ->
        tuple(roundKey.graphId, roundKey.round, marks)
    }

    // Column 3 holds the round mask; bits 0 through 30 select retained cuts.
    def rounds = channel.fromList((0..<params.region_filter_rounds).toList())
    def cutsByRound = cutEdges.combine(rounds).map { graphId, cuts, round ->
        tuple([graphId: graphId, round: round], cuts, round)
    }
    FILTER_ROWS_BY_BIT(cutsByRound, 3)
    TAKE_COLUMNS(FILTER_ROWS_BY_BIT.out.output, [1, 2])
    APPEND_TO_ROWS(TAKE_COLUMNS.out.output, 0)
    def roundEdgeMarks = APPEND_TO_ROWS.out.output.map { roundKey, marks ->
        tuple(roundKey.graphId, roundKey.round, marks)
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
        path { graphId, file ->
            file >> "${graphId}/region_filter/region_filter.log"
        }
    }

    graph_maps {
        mode 'copy'
        path { graphId, reportKey, file ->
            file >> "${graphId}/region_filter/${reportKey}/${file.name}"
        }
    }
}
