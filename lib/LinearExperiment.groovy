/** Plans one input's linear chain independently of tool options, files and Nextflow channels. */
class LinearExperiment {
    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message)
    }

    private static boolean name(Object value) {
        value instanceof String && !value.trim().isEmpty()
    }

    static List plan(Object stages, Object comparisons = null) {
        require(stages instanceof List && !stages.empty, 'stages must be a nonempty ordered list')
        def variantsById = [:]
        def batches = stages.collect { stage ->
            require(stage instanceof Map && name(stage.id) && name(stage.tool), 'Each stage needs an id and a tool')
            require(!variantsById.containsKey(stage.id), "Duplicate stage id: ${stage.id}")
            def unknown = stage.keySet() - ['id', 'tool', 'variants', 'defaults', 'repetitions']
            require(unknown.isEmpty(), "Unknown stage fields at ${stage.id}: ${unknown}")
            def defaults = stage.getOrDefault('defaults', [:])
            def variants = stage.getOrDefault('variants', [default: [:]])
            def repetitions = stage.getOrDefault('repetitions', 1)
            require(defaults instanceof Map && variants instanceof Map && !variants.isEmpty(),
                "Expected defaults and named variant maps at ${stage.id}")
            require(repetitions instanceof Integer && repetitions > 0, "Invalid repetitions at ${stage.id}")
            variantsById[stage.id] = variants.collectEntries { variant, overrides ->
                require(name(variant) && overrides instanceof Map, "Invalid variant at ${stage.id}: ${variant}")
                [(variant): defaults + overrides]
            }
            [id: stage.id, tool: stage.tool, repetitions: repetitions, trials: []]
        }

        // Each selector describes allowed variants on any subset of the stages.
        def selectors = comparisons == null ? [[:]] : comparisons
        require(selectors instanceof List && !selectors.empty, 'comparisons must be a nonempty list')
        selectors.each { selector ->
            require(selector instanceof Map, 'Each comparison must map stage ids to variant names')
            selector.each { id, variant ->
                require(variantsById[id]?.containsKey(variant) == true, "Unknown comparison: ${id}=${variant}")
            }
        }

        // Only grow prefixes that can still satisfy at least one selector. Overlapping
        // selectors reach the same trial once. Repetitions branch independently per parent.
        def parents = [[key: null, selectors: selectors]]
        batches.each { stage ->
            def children = []
            parents.each { parent ->
                variantsById[stage.id].each { variant, options ->
                    def matches = parent.selectors.findAll { !it.containsKey(stage.id) || it[stage.id] == variant }
                    if (matches) {
                        (1..stage.repetitions).each { repetition ->
                            def step = [stage: stage.id, variant: variant, repetition: repetition]
                            def key = (parent.key ?: []) + [step]
                            stage.trials << [key: key, parentKey: parent.key, variant: variant,
                                repetition: repetition, options: options]
                            children << [key: key, selectors: matches]
                        }
                    }
                }
            }
            parents = children
        }
        return batches
    }
}
