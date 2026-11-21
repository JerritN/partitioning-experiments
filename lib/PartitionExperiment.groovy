import groovy.json.JsonOutput

class PartitionExperiment {
    private static final Map OPTIONS = [
        region_filter: [
            integer: 'U k regions lloyd rounds min_rounds margin seed tau',
            number: 'eps region_factor terminal_fraction ball_fraction spread_fraction',
            string: 'terminals centers cut_side dump_pairs',
            flag: 'pin_ring closed no_fallback no_tiny_cuts verbose',
            factors: 'region_factors'
        ],
        mt_kahypar: [
            integer: 'blocks threads seed num_vcycles', number: 'epsilon',
            string: 'objective preset_type file_format edge_metadata_type c_rating_edge_metadata',
            flag: 'allow_empty_blocks quiet verbose enable_progress_bar show_detailed_timings initial_partition_relax_on_stall initial_partition_vcycle_fragments'
        ]
    ]

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message)
    }

    private static void checkMap(Object value, Collection allowed, String where) {
        require(value instanceof Map, "Expected a map at ${where}")
        def unknown = value.keySet() - allowed
        require(unknown.empty, "Unknown keys at ${where}: ${unknown}")
    }

    private static boolean label(Object value) {
        value instanceof String && !value.trim().isEmpty() && !value.find(/[\r\n\t]/)
    }

    private static void checkOptions(Object opts, String tool, String where) {
        def schema = OPTIONS[tool]
        checkMap(opts, schema.values().collectMany { it.tokenize() }, where)
        schema.each { type, names ->
            opts.subMap(names.tokenize()).each { key, value ->
                boolean valid
                switch (type) {
                    case 'integer': valid = value instanceof Integer || value instanceof Long; break
                    case 'number': valid = value instanceof Number; break
                    case 'string': valid = label(value); break
                    case 'flag': valid = value instanceof Boolean; break
                    default: valid = label(value) || (value instanceof List && !value.empty && value.every { it instanceof Number })
                }
                require(valid, "Invalid ${type} option at ${where}.${key}: ${value}")
            }
        }
    }

    private static Map stage(Object config, String tool) {
        checkMap(config, ['defaults', 'variants', 'repetitions'], tool)
        def defaults = config.getOrDefault('defaults', [:])
        checkOptions(defaults, tool, "${tool}.defaults")
        def reps = config.getOrDefault('repetitions', 1)
        require(reps instanceof Integer && reps > 0, "${tool}.repetitions must be a positive integer")
        require(config.variants instanceof Map && !config.variants.isEmpty(), "${tool}.variants must name at least one variant")
        def variants = config.variants.collectEntries { name, overrides ->
            def where = "${tool}.variants.${name}"
            require(label(name) && overrides instanceof Map, "Expected a named option map at ${where}")
            def opts = defaults + overrides
            if (tool == 'mt_kahypar') {
                opts = [file_format: 'metis', edge_metadata_type: 'natural_edge', c_rating_edge_metadata: 'ignore'] + opts
            }
            checkOptions(opts, tool, where)
            if (tool == 'region_filter') {
                require(opts.containsKey('k') != opts.containsKey('U'), "${where} requires exactly one of k or U")
                require((opts.k ?: opts.U ?: 0) > 0, "${where} requires positive k or U")
                require(opts.eps == null || opts.k != null, "${where}.eps requires k")
                require(!opts.no_fallback || opts.closed, "${where}.no_fallback requires closed")
            } else {
                require(opts.blocks != null && opts.blocks > 0 && opts.epsilon != null && opts.epsilon >= 0 &&
                    opts.objective != null && opts.preset_type != null, "${where} requires blocks, epsilon, objective and preset_type")
                require(opts.file_format == 'metis' && opts.edge_metadata_type == 'natural_edge', "${where} requires METIS input and natural_edge metadata")
                require(opts.threads == null || opts.threads > 0, "${where}.threads must be positive")
            }
            [(name): opts]
        }
        [variants: variants, repetitions: reps]
    }

    static Map parse(Map experiment) {
        checkMap(experiment, ['name','graphs','region_filter','mt_kahypar','comparisons'], 'experiment')
        require(label(experiment.name), 'experiment.name must be a nonempty string')
        def graphs = experiment.graphs
        require(graphs instanceof List && !graphs.empty && graphs.every { label(it) } &&
            graphs.toSet().size() == graphs.size(), 'experiment.graphs must list distinct graph paths')
        def filter = stage(experiment.region_filter, 'region_filter')
        def partition = stage(experiment.mt_kahypar, 'mt_kahypar')
        def pairs = experiment.getOrDefault('comparisons', null)
        if (!experiment.containsKey('comparisons')) {
            pairs = filter.variants.keySet().collectMany { f ->
                partition.variants.keySet().collect { p -> [filter: f, partition: p] }
            }
        }
        require(pairs instanceof List && !pairs.empty, 'comparisons must contain at least one pair')
        pairs.each { pair ->
            checkMap(pair, ['filter','partition'], 'comparisons')
            require(filter.variants.containsKey(pair.filter) && partition.variants.containsKey(pair.partition),
                "Unknown filter or partition variant in ${pair}")
        }
        require(pairs.toSet().size() == pairs.size(), 'Duplicate filter/partition comparison')
        [name: experiment.name, graphs: graphs, filter: filter, partition: partition,
            comparisons: pairs.groupBy { it.filter }.collectEntries { f, group -> [(f): group*.partition] }]
    }

    static String optionsJson(Map options) {
        JsonOutput.toJson(new TreeMap(options))
    }
}
