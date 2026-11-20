include { BUILD_PARTITIONING_TOOLS } from '../subworkflows/build_partitioning_tools.nf'
include { PARTITION_WITH_REGION_FILTER } from '../subworkflows/partition_with_region_filter.nf'
include { IMPORT_SQLPLOT_RESULTS } from '../modules/import_sqlplot_results.nf'

params {
    repository: String = "${params.project_path}/mt-kahypar"
    build_threads: Integer
    region_filter_revision: String
    mt_kahypar_revision: String
    graph_dir: String = "${params.project_path}/data"
    region_filter_k: Integer = 8
    filter_repetitions: Integer = 1
    repetitions: Integer = 1
    mt_kahypar_threads: Integer = 8
    mt_kahypar_blocks: Integer = 8
    mt_kahypar_epsilon: Float = 0.03f
    mt_kahypar_objective: String = "cut"
    mt_kahypar_preset: String = "default"
}

workflow {
    main:
    assert params.filter_repetitions >= 1 : 'filter_repetitions must be positive'
    assert params.repetitions >= 1 : 'repetitions must be positive'

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
    def runs = graphs.combine(ratingOpts)
        .combine(channel.fromList((1..params.filter_repetitions).toList()))
        .combine(channel.fromList((1..params.repetitions).toList()))
        .map { graph, rating, filterRep, repetition ->
            def context = [graph: graph.baseName, filterRepetition: filterRep, repetition: repetition]
            tuple(context, graph, filterOpts, sharedKahyparOpts + rating)
        }
    PARTITION_WITH_REGION_FILTER(runs, BUILD_PARTITIONING_TOOLS.out.region_filter, BUILD_PARTITIONING_TOOLS.out.mt_kahypar)

    def records = PARTITION_WITH_REGION_FILTER.out.results.map { context, result ->
        SqlPlotResult.withFields(result.text, [
            graph_id: context.graph,
            rating_policy: context.kahyparOpts.c_rating_edge_metadata,
            region_filter_k: context.filterKey.opts.k,
            filter_repetition: context.filterKey.repetition,
            repetition: context.repetition,
            region_filter_commit: context.filterKey.commit,
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
