include { BUILD_PARTITIONING_TOOLS } from '../subworkflows/build_partitioning_tools.nf'
include { BENCHMARK_PARTITIONS } from '../subworkflows/benchmark_partitions.nf'

params {
    experiment: String
    repository: String = "${params.project_path}/mt-kahypar"
    graph_dir: String = "${params.project_path}/data"
    build_threads: Integer
    region_filter_revision: String
    mt_kahypar_revision: String
}

def prepareTrials(batch, defaults) {
    batch.requests.collect { trial ->
        OptionChecks.checkMap(trial.inputs, ['options'], batch.id)
        def options = trial.inputs.getOrDefault('options', [:])
        checkInput(options instanceof Map, "Expected an options map for ${batch.id}")
        trial + [options: defaults + options]
    }
}

def checkInput(condition, message) {
    if (!condition) throw new IllegalArgumentException(message)
}

def planExperiment(experiment) {
    OptionChecks.checkMap(experiment, ['name', 'dimensions', 'stages', 'selections'], 'experiment')
    checkInput(experiment.name instanceof String && experiment.name.trim(), 'Expected an experiment name')
    def dimensions = LinearExperiment.dimensions(experiment.getOrDefault('dimensions', [:]))
    def stages = LinearExperiment.stages(experiment.stages, dimensions)
    def expected = ['metis_graph', 'region_filter', 'mt_kahypar']
    checkInput(stages*.tool == expected, "Expected stages ${expected}; received ${stages*.tool}")
    def selections = experiment.getOrDefault('selections', [[:]])
    LinearExperiment.checkSelections(selections, dimensions)
    return LinearExperiment.plan(dimensions, stages, selections)
}

def optionsJson(options) {
    groovy.json.JsonOutput.toJson(new TreeMap(options))
}

workflow {
    main:
    def experiment = ExperimentFile.read(file(params.experiment, checkIfExists: true))
    def stages = planExperiment(experiment)
    def dataDir = file(params.graph_dir)

    // Resolve and validate selected inputs and tool settings before starting builds.
    def graphs = stages[0].requests.collectEntries { request ->
        def opts = request.inputs
        assert opts.keySet() == ['path'].toSet() && opts.path instanceof String && opts.path.trim() :
            "Expected a graph path for ${request.choices}"
        def path = dataDir.resolve(opts.path).normalize()
        assert path.isFile() : "Missing experiment graph: ${path}"
        [(request.key): [id: opts.path, file: path]]
    }
    def filterTrials = prepareTrials(stages[1], [:])
    def partitionTrials = prepareTrials(stages[2], [
        file_format: 'metis', edge_metadata_type: 'natural_edge', c_rating_edge_metadata: 'ignore'
    ])
    partitionTrials.each { trial ->
        checkInput(trial.options.file_format == 'metis' && trial.options.edge_metadata_type == 'natural_edge',
            'This workflow supplies a METIS graph and natural-edge metadata')
    }
    def filterByKey = filterTrials.collectEntries { trial -> [(trial.key): trial] }

    BUILD_PARTITIONING_TOOLS(params.repository, params.build_threads, [
        region_filter: params.region_filter + [revision: params.region_filter_revision],
        mt_kahypar: params.mt_kahypar + [revision: params.mt_kahypar_revision]
    ])

    def filters = channel.fromList(filterTrials).map { trial ->
        tuple(trial.key, graphs[trial.parentKey].file, trial.options)
    }
    def runs = channel.fromList(partitionTrials)
    def partitions = runs.map { trial -> tuple(trial.key, trial.parentKey, trial.options) }
    def metadata = runs.map { trial ->
        def filter = filterByKey[trial.parentKey]
        def fields = [
            experiment_name: experiment.name,
            graph_id: graphs[filter.parentKey].id,
            rating_policy: trial.options.c_rating_edge_metadata,
            dimension_choices: optionsJson(trial.choices),
            region_filter_options: optionsJson(filter.options),
            mt_kahypar_options: optionsJson(trial.options)
        ]
        if (filter.options.k != null) fields.region_filter_k = filter.options.k
        if (filter.options.U != null) fields.region_filter_u = filter.options.U
        tuple(trial.key, fields)
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
