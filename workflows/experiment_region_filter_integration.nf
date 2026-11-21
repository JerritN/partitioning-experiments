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
    def experiment = params.experiment
    assert (experiment.keySet() - ['name', 'graphs', 'stages', 'comparisons']).isEmpty() : 'Unknown experiment field'
    assert experiment.name instanceof String && experiment.name.trim() : 'Expected an experiment name'
    assert experiment.graphs instanceof List && experiment.graphs && experiment.graphs.every {
        it instanceof String && it.trim()
    } && experiment.graphs.unique(false) == experiment.graphs : 'Expected distinct graph paths'
    assert experiment.stages instanceof List && experiment.stages.collect { it?.tool } == ['region_filter', 'mt_kahypar'] :
        'This workflow requires region_filter followed by mt_kahypar'
    def stages = LinearExperiment.plan(experiment.stages, experiment.comparisons)
    def filterStage = stages[0]
    def partitionStage = stages[1]
    def dataDir = file(params.graph_dir)
    def graphs = experiment.graphs.collect { graphId ->
        def graph = dataDir.resolve(graphId).normalize()
        assert graph.isFile() : "Missing experiment graph: ${graph}"
        tuple(graphId, graph)
    }

    // Validate the selected variants before building. Option interpretation belongs here.
    def options = stages.collectEntries { stage ->
        def byVariant = stage.trials.unique(false) { it.variant }.collectEntries { trial ->
            [(trial.variant): PartitionExperiment.options(stage.tool, trial.variant, trial.options)]
        }
        [(stage.id): byVariant]
    }

    BUILD_PARTITIONING_TOOLS(params.repository, params.build_threads, [
        region_filter: params.region_filter + [revision: params.region_filter_revision],
        mt_kahypar: params.mt_kahypar + [revision: params.mt_kahypar_revision]
    ])

    // The plan describes one input. Scope its keys to the graph before matching artifacts.
    def filters = channel.fromList(graphs).combine(channel.fromList(filterStage.trials))
        .map { graphId, graph, trial ->
            tuple([graph: graphId, trial: trial.key], graph, options[filterStage.id][trial.variant])
        }
    def runs = channel.fromList(experiment.graphs).combine(channel.fromList(partitionStage.trials))
    def partitions = runs.map { graphId, trial ->
        tuple([graph: graphId, trial: trial.key], [graph: graphId, trial: trial.parentKey],
            options[partitionStage.id][trial.variant])
    }
    def metadata = runs.map { graphId, trial ->
        def parent = trial.parentKey.last()
        def filterOpts = options[filterStage.id][parent.variant]
        def opts = options[partitionStage.id][trial.variant]
        def fields = [
            experiment_name: experiment.name,
            graph_id: graphId,
            filter_variant: parent.variant,
            partition_variant: trial.variant,
            rating_policy: opts.c_rating_edge_metadata,
            filter_repetition: parent.repetition,
            repetition: trial.repetition,
            region_filter_options: PartitionExperiment.optionsJson(filterOpts),
            mt_kahypar_options: PartitionExperiment.optionsJson(opts)
        ]
        if (filterOpts.k != null) fields.region_filter_k = filterOpts.k
        if (filterOpts.U != null) fields.region_filter_u = filterOpts.U
        tuple([graph: graphId, trial: trial.key], fields)
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
