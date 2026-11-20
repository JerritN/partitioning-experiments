include { BUILD_CMAKE_FROM_GIT } from '../subworkflows/build_cmake_from_git.nf'
include { REGION_FILTER } from '../modules/region_filter.nf'
include { TAKE_COLUMNS } from '../modules/take_columns.nf'
include { MT_KAHYPAR } from '../modules/mt_kahypar.nf'
include { IMPORT_SQLPLOT_RESULTS } from '../modules/import_sqlplot_results.nf'

params {
    repository: String = "${params.project_path}/mt-kahypar"
    build_threads: Integer
    region_filter_revision: String
    mt_kahypar_revision: String
    graph_dir: String = "${params.project_path}/data"
    region_filter_k: Integer = 8
    repetitions: Integer = 1
    mt_kahypar_threads: Integer = 8
    mt_kahypar_blocks: Integer = 8
    mt_kahypar_epsilon: Float = 0.03f
    mt_kahypar_objective: String = "cut"
    mt_kahypar_preset: String = "default"
}

workflow {
    main:
    assert params.repetitions >= 1 : 'repetitions must be positive'

    // Build the two tools at their requested revisions.
    def kahyparBuildOpts = [
        preset: params.mt_kahypar.cmake_preset,
        definitions: params.mt_kahypar.definitions,
        target: params.mt_kahypar.target,
        binary: params.mt_kahypar.binary,
        threads: params.build_threads
    ]
    def regionFilterBuildOpts = [
        preset: params.region_filter.cmake_preset,
        target: params.region_filter.target,
        binary: params.region_filter.binary,
        threads: params.build_threads
    ]
    def buildRequests = channel.of(
        tuple([tool: 'kahypar'], params.repository, params.mt_kahypar_revision, kahyparBuildOpts),
        tuple([tool: 'regionFilter'], params.repository, params.region_filter_revision, regionFilterBuildOpts)
    )
    BUILD_CMAKE_FROM_GIT(buildRequests)
    def binaries = BUILD_CMAKE_FROM_GIT.out.binary.branch { context, _binary ->
        kahypar: context.tool == 'kahypar'
        regionFilter: context.tool == 'regionFilter'
    }
    def kahyparExecutable = binaries.kahypar
        .map { context, binary -> tuple(context.commit, binary) }
    def regionFilterExecutable = binaries.regionFilter
        .map { context, binary -> tuple(context.commit, binary) }

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
        k: params.region_filter_k
    ])
    
    def regionFilterInputs = graphs
        .combine(regionFilterExecutable)
        .combine(regionFilterOpts)
        .map { context, graph, commit, executable, opts ->
            tuple(context + [regionFilterOpts: opts, regionFilterCommit: commit], executable, graph, opts)
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
        preset_type: params.mt_kahypar_preset,
    ]
    def ratingOpts = channel.fromList([
        [c_rating_edge_metadata: 'ignore'],
        [c_rating_edge_metadata: 'skip_natural_edge'],
        [c_rating_edge_metadata: 'natural_edge_contribute_zero'],
        [c_rating_edge_metadata: 'natural_edge_contribute_negative'],
    ])
    def trials = ratingOpts.combine(channel.fromList((1..params.repetitions).toList()))
        .map { ratingOpt, repetition ->
            tuple(repetition, sharedKahyparOpts + ratingOpt)
        }
    def kahyparInputs = naturalEdges
        .combine(kahyparExecutable)
        .combine(trials)
        .map { context, metadata, commit, executable, repetition, opts ->
            tuple(
                context + [kahyparOpts: opts, kahyparCommit: commit, repetition: repetition],
                executable,
                context.graphFile,
                [],
                metadata,
                opts
            )
        }
    
    MT_KAHYPAR(kahyparInputs)

    def records = MT_KAHYPAR.out.result.map { context, result ->
        SqlPlotResult.withFields(result.text, [
            graph_id: context.graph,
            rating_policy: context.kahyparOpts.c_rating_edge_metadata,
            region_filter_k: context.regionFilterOpts.k,
            repetition: context.repetition,
            region_filter_commit: context.regionFilterCommit,
            mt_kahypar_commit: context.kahyparCommit
        ])
    }.collectFile(name: 'runs.result', newLine: true, sort: true)
    IMPORT_SQLPLOT_RESULTS(records, 'runs')

    publish:
    run_database = IMPORT_SQLPLOT_RESULTS.out.database
}

output {
    run_database {
        mode 'copy'
    }
}
