class ExperimentParser {
    static ExperimentDefinition parse(Map document) {
        MapChecks.requireOnlyKeys(document, ['name', 'dimensions', 'stages', 'selections'], 'experiment')
        def rawDimensions = document.getOrDefault('dimensions', [:])
        require(rawDimensions instanceof Map, 'dimensions must be a map')
        def dimensions = rawDimensions.collectEntries { name, choices ->
            [(name): normalizeChoices(name, choices)]
        }
        require(document.name instanceof String, 'Expected an experiment name')
        require(document.stages instanceof List, 'Expected an ordered list of stages')
        def stages = []
        document.stages.eachWithIndex { stage, index ->
            def location = "stage ${index + 1}"
            MapChecks.requireOnlyKeys(stage, ['tool', 'id', 'inputs', 'vary'], location)
            require(stage.tool instanceof String, "${location} requires a tool")
            require(!stage.containsKey('id') || stage.id instanceof String, "Invalid id at ${location}")
            def inputs = stage.getOrDefault('inputs', [:])
            def vary = stage.getOrDefault('vary', [])
            require(inputs instanceof Map && vary instanceof List, "Expected an inputs map and vary list at ${location}")
            stages << new StageDefinition(stage.tool, parseInputs(inputs), vary, stage.id)
        }
        def selections = document.getOrDefault('selections', [[:]])
        require(selections instanceof List, 'selections must be a list')
        return new ExperimentDefinition(document.name, dimensions, stages, selections)
    }

    private static Map normalizeChoices(name, choices) {
        if (choices instanceof Map) return choices
        require(choices instanceof List, "Expected named choices or a list for ${name}")
        require(choices.toSet().size() == choices.size(), "Duplicate choices in ${name}")
        choices.collectEntries { label -> [(label): label] }
    }

    private static Object parseInputs(value) {
        if (value instanceof List) return value.collect { parseInputs(it) }
        if (value instanceof Map) return value.collectEntries { k, v -> [(k): parseInputs(v)] }
        if (!(value instanceof String) || !value.contains('${')) return value
        def match = value =~ /^\$\{([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\}$/
        require(match.matches(), "Expected a whole-value dimension reference: ${value}")
        def path = match.group(1).tokenize('.')
        return new DimensionReference(path.first(), path.tail())
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message)
    }
}
