package experiment

import util.Assertions

class ExperimentParser {
    static ExperimentDefinition parse(Map document) {
        Assertions.assertOnlyKeys(document, ['name', 'dimensions', 'stages', 'selections'], 'experiment')
        def rawDimensions = document.getOrDefault('dimensions', [:])
        Assertions.assertThat(rawDimensions instanceof Map, 'dimensions must be a map')
        def dimensions = rawDimensions.collectEntries { name, choices ->
            [(name): normalizeChoices(name, choices)]
        }
        Assertions.assertThat(document.name instanceof String, 'Expected an experiment name')
        Assertions.assertThat(document.stages instanceof List, 'Expected an ordered list of stages')
        def stages = []
        document.stages.eachWithIndex { stage, index ->
            def location = "stage ${index + 1}"
            Assertions.assertOnlyKeys(stage, ['tool', 'id', 'inputs', 'vary'], location)
            Assertions.assertThat(stage.tool instanceof String, "${location} requires a tool")
            Assertions.assertThat(!stage.containsKey('id') || stage.id instanceof String, "Invalid id at ${location}")
            def inputs = stage.getOrDefault('inputs', [:])
            def vary = stage.getOrDefault('vary', [])
            Assertions.assertThat(inputs instanceof Map && vary instanceof List, "Expected an inputs map and vary list at ${location}")
            stages << new StageDefinition(stage.tool, parseInputs(inputs), vary, stage.id)
        }
        def selections = document.getOrDefault('selections', [[:]])
        Assertions.assertThat(selections instanceof List, 'selections must be a list')
        return new ExperimentDefinition(document.name, dimensions, stages, selections)
    }

    private static Map normalizeChoices(name, choices) {
        if (choices instanceof Map) return choices
        Assertions.assertThat(choices instanceof List, "Expected named choices or a list for ${name}")
        Assertions.assertThat(choices.toSet().size() == choices.size(), "Duplicate choices in ${name}")
        choices.collectEntries { label -> [(label): label] }
    }

    private static Object parseInputs(value) {
        if (value instanceof List) return value.collect { parseInputs(it) }
        if (value instanceof Map) return value.collectEntries { k, v -> [(k): parseInputs(v)] }
        if (!(value instanceof String) || !value.contains('${')) return value
        def match = value =~ /^\$\{([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\}$/
        Assertions.assertThat(match.matches(), "Expected a whole-value dimension reference: ${value}")
        def path = match.group(1).tokenize('.')
        return new DimensionReference(path.first(), path.tail())
    }
}
