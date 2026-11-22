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

def resolveGraphInput(run, graphDir, stageLabel) {
    def where = "${stageLabel}.inputs for ${run.choices}"
    MapChecks.requireOnlyKeys(run.inputs, ['path'], where)
    def name = run.inputs.path
    assert name instanceof String && name.trim() : "Expected a nonempty graph path at ${where}"
    def path = graphDir.resolve(name).normalize()
    assert path.isFile() : "Missing graph at ${where}: ${path}"
    return [id: name, file: path]
}

def readToolOptions(run, stageLabel) {
    def where = "${stageLabel}.inputs for ${run.choices}"
    MapChecks.requireOnlyKeys(run.inputs, ['options'], where)
    def options = run.inputs.getOrDefault('options', [:])
    assert options instanceof Map : "Expected an options map at ${where}"
    return options
}

def preparePartitionerOptions(run, stageLabel) {
    def defaults = [file_format: 'metis', edge_metadata_type: 'natural_edge', c_rating_edge_metadata: 'ignore']
    def options = defaults + readToolOptions(run, stageLabel)
    assert options.file_format == 'metis' && options.edge_metadata_type == 'natural_edge' :
        "${stageLabel} receives a METIS graph and natural-edge metadata for ${run.choices}"
    return options
}

def sortedJson(fields) {
    groovy.json.JsonOutput.toJson(new TreeMap(fields))
}

workflow {
    main:
    def experiment = ExperimentFile.read(file(params.experiment, checkIfExists: true))
    def plannedStages = LinearExperiment.plan(experiment)
    LinearExperiment.verifyStageSequence(plannedStages, ['metis_graph', 'region_filter', 'mt_kahypar'])
    def (graphStage, filterStage, partitionStage) = plannedStages
    def graphDir = file(params.graph_dir)

    // Validate resolved named inputs while adapting them to process requests, before starting builds.
    def graphs = graphStage.runs.collectEntries { run ->
        [(run.key): resolveGraphInput(run, graphDir, graphStage.id)]
    }
    def filterRuns = filterStage.runs.collect { run ->
        run + [options: readToolOptions(run, filterStage.id)]
    }
    def partitionRuns = partitionStage.runs.collect { run ->
        run + [options: preparePartitionerOptions(run, partitionStage.id)]
    }
    def filterRunByKey = filterRuns.collectEntries { run -> [(run.key): run] }

    BUILD_PARTITIONING_TOOLS(params.repository, params.build_threads, [
        region_filter: params.region_filter + [revision: params.region_filter_revision],
        mt_kahypar: params.mt_kahypar + [revision: params.mt_kahypar_revision]
    ])

    def filterRequests = channel.fromList(filterRuns).map { run ->
        tuple(run.key, graphs[run.parentKey].file, run.options)
    }
    def partitionRunChannel = channel.fromList(partitionRuns)
    def partitionRequests = partitionRunChannel.map { run -> tuple(run.key, run.parentKey, run.options) }
    def metadata = partitionRunChannel.map { run ->
        def filter = filterRunByKey[run.parentKey]
        def fields = [
            experiment_name: experiment.name,
            graph_id: graphs[filter.parentKey].id,
            rating_policy: run.options.c_rating_edge_metadata,
            dimension_choices: sortedJson(run.choices),
            region_filter_options: sortedJson(filter.options),
            mt_kahypar_options: sortedJson(run.options)
        ]
        if (filter.options.k != null) fields.region_filter_k = filter.options.k
        if (filter.options.U != null) fields.region_filter_u = filter.options.U
        tuple(run.key, fields)
    }
    BENCHMARK_PARTITIONS(filterRequests, partitionRequests, metadata,
        BUILD_PARTITIONING_TOOLS.out.region_filter, BUILD_PARTITIONING_TOOLS.out.mt_kahypar)

    publish:
    run_database = BENCHMARK_PARTITIONS.out.database
}

output {
    run_database {
        mode 'copy'
    }
}
