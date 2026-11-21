include { BUILD_PARTITIONING_TOOLS } from '../subworkflows/build_partitioning_tools.nf'
include { PARTITION_WITH_REGION_FILTER } from '../subworkflows/partition_with_region_filter.nf'
include { FILTER_EDGES_BY_PARTITION } from '../modules/filter_edges_by_partition.nf'
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
    // This experiment shares one filter execution per graph and filter repetition.
    def filters = graphs.combine(channel.fromList((1..params.filter_repetitions).toList()))
        .map { graph, repetition -> tuple([graphId: graph.baseName, repetition: repetition], graph, filterOpts) }
    def partitions = filters.map { filterKey, _graph, _opts -> filterKey }
        .combine(ratingOpts)
        .combine(channel.fromList((1..params.repetitions).toList()))
        .map { filterKey, rating, repetition ->
            def key = [filter: filterKey, policy: rating.c_rating_edge_metadata, repetition: repetition]
            tuple(key, filterKey, sharedKahyparOpts + rating)
        }
    def filterTools = BUILD_PARTITIONING_TOOLS.out.region_filter
    def partitionTools = BUILD_PARTITIONING_TOOLS.out.mt_kahypar
    PARTITION_WITH_REGION_FILTER(
        filters, partitions,
        filterTools.map { _commit, executable -> executable },
        partitionTools.map { _commit, executable -> executable }
    )

    // Several partitions share the edges produced by one graph/filter repetition.
    def naturalEdges = PARTITION_WITH_REGION_FILTER.out.natural_edges
    def totals = naturalEdges.map { filterKey, edges -> tuple(filterKey, FileUtils.countRows(edges)) }
    def cutInputs = PARTITION_WITH_REGION_FILTER.out.partitions
        .map { key, partition -> tuple(key.filter, key, partition) }
        .combine(naturalEdges, by: 0)
        .map { _filterKey, key, partition, edges -> tuple(key, partition, edges) }
    FILTER_EDGES_BY_PARTITION(cutInputs, 'between')

    def counts = FILTER_EDGES_BY_PARTITION.out.output
        .map { key, edges -> tuple(key.filter, key, FileUtils.countRows(edges)) }
        .combine(totals, by: 0)
        .map { _filterKey, key, cut, total -> tuple(key, cut, total) }

    def records = PARTITION_WITH_REGION_FILTER.out.results
        .join(counts, failOnDuplicate: true, failOnMismatch: true)
        .combine(filterTools.map { commit, _executable -> commit })
        .combine(partitionTools.map { commit, _executable -> commit })
        .map { key, result, cut, total, filterCommit, partitionCommit ->
            SqlPlotResult.withFields(result.text, [
                natural_edges_cut: cut,
                total_natural_edges: total,
                graph_id: key.filter.graphId,
                rating_policy: key.policy,
                region_filter_k: filterOpts.k,
                filter_repetition: key.filter.repetition,
                repetition: key.repetition,
                region_filter_commit: filterCommit,
                mt_kahypar_commit: partitionCommit
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
