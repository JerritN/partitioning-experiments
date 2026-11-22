package experiment

import util.Assertions

class ExperimentParser {
    static ExperimentDefinition parse(Map document) {
        Assertions.assertOnlyKeys(document, ['name', 'dimensions', 'stages', 'selections'], 'experiment')

        Assertions.assertThat(isName(document.name), 'Expected an experiment name')

        def rawDimensions = document.getOrDefault('dimensions', [:])
        Assertions.assertThat(rawDimensions instanceof Map, 'dimensions must be a map')
        def dimensions = rawDimensions.collectEntries { name, choices ->
            Assertions.assertThat(isIdentifier(name), "Invalid dimension name: ${name}")
            [(name): normalizeChoices(name, choices)]
        }

        Assertions.assertThat(document.stages instanceof List && !document.stages.empty, 'Expected an ordered list of stages')
        def stages = []
        document.stages.eachWithIndex { stage, index ->
            def location = "stage ${index + 1}"
            Assertions.assertOnlyKeys(stage, ['tool', 'id', 'inputs', 'vary'], location)

            Assertions.assertThat(isName(stage.tool), "${location} requires a tool")
            Assertions.assertThat(!stage.containsKey('id') || isName(stage.id), "Invalid id at ${location}")

            def inputs = stage.getOrDefault('inputs', [:])
            def vary = stage.getOrDefault('vary', [])
            Assertions.assertThat(inputs instanceof Map && vary instanceof List, "Expected an inputs map and vary list at ${location}")
            Assertions.assertThat(vary.every { isIdentifier(it) }, "Expected dimension names in vary at ${location}")

            stages << new StageDefinition(stage.tool, parseInputs(inputs), vary, stage.id)
        }

        def selections = document.getOrDefault('selections', [[:]])
        Assertions.assertThat(selections instanceof List && !selections.empty, 'Expected a nonempty list of selections')
        selections.each { selection ->
            Assertions.assertThat(selection instanceof Map, 'Expected a selection map')
            selection.each { name, label ->
                Assertions.assertThat(isIdentifier(name) && isLabel(label), "Invalid selection: ${name}=${label}")
            }
        }

        return new ExperimentDefinition(document.name, dimensions, stages, selections)
    }

    private static boolean isName(value) {
        value instanceof String && !value.trim().isEmpty()
    }

    private static boolean isIdentifier(value) {
        value instanceof String && value ==~ /[A-Za-z_][A-Za-z0-9_]*/
    }

    private static boolean isLabel(value) {
        isName(value) || value instanceof Number || value instanceof Boolean
    }

    private static Map normalizeChoices(name, choices) {
        if (choices instanceof Map) {
            Assertions.assertThat(!choices.isEmpty() && choices.keySet().every { isLabel(it) }, "Expected named choices for ${name}")
            return choices
        }
        Assertions.assertThat(choices instanceof List && !choices.empty && choices.every { isLabel(it) }, "Expected named choices or a nonempty list of labels for ${name}")
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
