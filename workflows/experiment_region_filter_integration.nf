include { BUILD_PARTITIONING_TOOLS } from '../subworkflows/build_partitioning_tools.nf'
include { BENCHMARK_PARTITIONS } from '../subworkflows/benchmark_partitions.nf'

params {
    experiment: Map
    repository: String = "${params.project_path}/mt-kahypar"
    graph_dir: String = "${params.project_path}/data"
    build_threads: Integer
    region_filter_revision: String
    mt_kahypar_revision: String
}

workflow {
    main:
    def plan = PartitionExperiment.parse(params.experiment)
    def dataDir = file(params.graph_dir)
    def graphs = plan.graphs.collect { graphId ->
        def graph = dataDir.resolve(graphId).normalize()
        assert graph.isFile() : "Missing experiment graph: ${graph}"
        tuple(graphId, graph)
    }

    BUILD_PARTITIONING_TOOLS(params.repository, params.build_threads, [
        region_filter: params.region_filter + [revision: params.region_filter_revision],
        mt_kahypar: params.mt_kahypar + [revision: params.mt_kahypar_revision]
    ])

    // A named filter trial is shared by every partition variant that references it.
    def filters = channel.fromList(graphs)
        .combine(channel.fromList(plan.comparisons.keySet().toList()))
        .combine(channel.fromList((1..plan.filter.repetitions).toList()))
        .map { graphId, graph, variant, repetition ->
            def key = [graph: graphId, variant: variant, repetition: repetition]
            tuple(key, graph, plan.filter.variants[variant])
        }
    def partitions = filters.flatMap { filterKey, _graph, _opts ->
        plan.comparisons[filterKey.variant].collectMany { variant ->
            (1..plan.partition.repetitions).collect { repetition ->
                def key = [filter: filterKey, variant: variant, repetition: repetition]
                tuple(key, filterKey, plan.partition.variants[variant])
            }
        }
    }
    def metadata = partitions.map { key, filterKey, opts ->
        def filterOpts = plan.filter.variants[filterKey.variant]
        def fields = [
            experiment_name: plan.name,
            graph_id: filterKey.graph,
            filter_variant: filterKey.variant,
            partition_variant: key.variant,
            rating_policy: opts.c_rating_edge_metadata,
            filter_repetition: filterKey.repetition,
            repetition: key.repetition,
            region_filter_options: PartitionExperiment.optionsJson(filterOpts),
            mt_kahypar_options: PartitionExperiment.optionsJson(opts)
        ]
        if (filterOpts.k != null) fields.region_filter_k = filterOpts.k
        if (filterOpts.U != null) fields.region_filter_u = filterOpts.U
        tuple(key, fields)
    }
    BENCHMARK_PARTITIONS(filters, partitions, metadata,
        BUILD_PARTITIONING_TOOLS.out.region_filter, BUILD_PARTITIONING_TOOLS.out.mt_kahypar)

    publish:
    run_database = BENCHMARK_PARTITIONS.out.database
}

output {
    run_database {
        mode 'copy'
    }
}
