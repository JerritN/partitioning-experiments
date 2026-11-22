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

def prepareTrials(batch, schema) {
    def checked = [:]
    batch.requests.collect { trial ->
        if (!checked.containsKey(trial.options)) {
            def where = "${batch.id} for ${trial.choices}"
            checked[trial.options] = toolOptions(batch.tool, schema, where, trial.options)
        }
        trial + [options: checked[trial.options]]
    }
}

/** Validate and complete the options used by this specific integration workflow. */
def toolOptions(tool, schema, where, supplied) {
    def opts = supplied
    if (tool == 'mt_kahypar') {
        opts = [file_format: 'metis', edge_metadata_type: 'natural_edge', c_rating_edge_metadata: 'ignore'] + opts
    }
    OptionChecks.checkOptions(opts, schema, where)
    if (tool == 'region_filter') {
        checkInput(opts.containsKey('k') != opts.containsKey('U'), "${where} requires exactly one of k or U")
        checkInput((opts.k ?: opts.U ?: 0) > 0, "${where} requires positive k or U")
        checkInput(opts.eps == null || opts.k != null, "${where}.eps requires k")
        checkInput(!opts.no_fallback || opts.closed, "${where}.no_fallback requires closed")
    } else {
        checkInput(opts.blocks != null && opts.blocks > 0 && opts.epsilon != null && opts.epsilon >= 0 &&
            opts.objective != null && opts.preset_type != null, "${where} requires blocks, epsilon, objective and preset_type")
        checkInput(opts.file_format == 'metis' && opts.edge_metadata_type == 'natural_edge', "${where} requires METIS input and natural_edge metadata")
        checkInput(opts.threads == null || opts.threads > 0, "${where}.threads must be positive")
    }
    return opts
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
        def opts = request.options
        assert opts.keySet() == ['path'].toSet() && opts.path instanceof String && opts.path.trim() :
            "Expected a graph path for ${request.choices}"
        def path = dataDir.resolve(opts.path).normalize()
        assert path.isFile() : "Missing experiment graph: ${path}"
        [(request.key): [id: opts.path, file: path]]
    }
    def schemas = [
        region_filter: [
            integer: 'U k regions lloyd rounds min_rounds margin seed tau',
            number: 'eps region_factor terminal_fraction ball_fraction spread_fraction',
            string: 'terminals centers cut_side dump_pairs',
            flag: 'pin_ring closed no_fallback no_tiny_cuts verbose',
            stringOrNumbers: 'region_factors'
        ],
        mt_kahypar: [
            integer: 'blocks threads seed num_vcycles', number: 'epsilon',
            string: 'objective preset_type file_format edge_metadata_type c_rating_edge_metadata',
            flag: 'allow_empty_blocks quiet verbose enable_progress_bar show_detailed_timings initial_partition_relax_on_stall initial_partition_vcycle_fragments'
        ]
    ]
    def filterTrials = prepareTrials(stages[1], schemas.region_filter)
    def partitionTrials = prepareTrials(stages[2], schemas.mt_kahypar)
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
