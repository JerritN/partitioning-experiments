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

def graphFor(batch, run, dataDir) {
    def where = "${batch.id}.inputs for ${run.choices}"
    OptionChecks.checkMap(run.inputs, ['path'], where)
    def name = run.inputs.path
    assert name instanceof String && name.trim() : "Expected a nonempty graph path at ${where}"
    def path = dataDir.resolve(name).normalize()
    assert path.isFile() : "Missing graph at ${where}: ${path}"
    return [id: name, file: path]
}

def optionsFor(batch, run) {
    def where = "${batch.id}.inputs for ${run.choices}"
    OptionChecks.checkMap(run.inputs, ['options'], where)
    def options = run.inputs.getOrDefault('options', [:])
    assert options instanceof Map : "Expected an options map at ${where}"
    return options
}

def partitionOptionsFor(batch, run) {
    def defaults = [file_format: 'metis', edge_metadata_type: 'natural_edge', c_rating_edge_metadata: 'ignore']
    def options = defaults + optionsFor(batch, run)
    assert options.file_format == 'metis' && options.edge_metadata_type == 'natural_edge' :
        "${batch.id} receives a METIS graph and natural-edge metadata for ${run.choices}"
    return options
}

def optionsJson(options) {
    groovy.json.JsonOutput.toJson(new TreeMap(options))
}

workflow {
    main:
    def experiment = ExperimentFile.read(file(params.experiment, checkIfExists: true))
    def batches = LinearExperiment.plan(experiment)
    LinearExperiment.verifyStageSequence(batches, ['metis_graph', 'region_filter', 'mt_kahypar'])
    def (graphStage, filterStage, partitionStage) = batches
    def dataDir = file(params.graph_dir)

    // Validate resolved named inputs while adapting them to process requests, before starting builds.
    def graphs = graphStage.requests.collectEntries { run ->
        [(run.key): graphFor(graphStage, run, dataDir)]
    }
    def filterTrials = filterStage.requests.collect { run ->
        run + [options: optionsFor(filterStage, run)]
    }
    def partitionTrials = partitionStage.requests.collect { run ->
        run + [options: partitionOptionsFor(partitionStage, run)]
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
