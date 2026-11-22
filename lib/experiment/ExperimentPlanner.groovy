package experiment

import util.Assertions

class ExperimentPlanner {
    private final ExperimentDefinition definition

    private ExperimentPlanner(ExperimentDefinition definition) {
        this.definition = definition
    }

    static Experiment plan(ExperimentDefinition definition) {
        return new ExperimentPlanner(definition).expandStages()
    }

    private Experiment expandStages() {
        def dimensionsByStage = validateDefinition()
        def stages = []
        def upstreamRuns = [new PlannedRun(null, null, [:], [:])]
        definition.stages.eachWithIndex { stage, index ->
            def planned = planStage(stage, index + 1, upstreamRuns, dimensionsByStage[index])
            stages << planned
            upstreamRuns = planned.runs
        }
        return new Experiment(definition.name, stages)
    }

    private List<Set> validateDefinition() {
        Assertions.assertThat(definition.name?.trim() as boolean, 'Expected an experiment name')
        def stages = definition.stages
        Assertions.assertThat(stages && stages.every { it instanceof StageDefinition }, 'Expected at least one stage definition')
        def dimensions = definition.dimensions
        Assertions.assertThat(dimensions != null, 'Expected a dimensions map')
        dimensions.each { dimension, choices ->
            Assertions.assertThat(dimension instanceof String && dimension ==~ /[A-Za-z_][A-Za-z0-9_]*/, "Invalid dimension name: ${dimension}")
            Assertions.assertThat(choices instanceof Map && !choices.isEmpty() && choices.keySet().every { validLabel(it) },
                "Expected named choices for dimension ${dimension}")
        }
        def ids = stages*.id.findAll { it != null }
        Assertions.assertThat(ids.size() == ids.toSet().size(), "Duplicate stage ids: ${ids}")
        def dimensionsByStage = stages.collect { stage ->
            Assertions.assertThat(stage.tool?.trim() && (stage.id == null || stage.id.trim()), 'Expected nonempty stage names')
            Assertions.assertThat(stage.inputTemplate != null && stage.vary != null, "Expected inputs and vary for ${stage.tool}")
            def used = new LinkedHashSet(stage.vary)
            collectReferencedDimensions(stage.inputTemplate, used)
            def unknown = used - dimensions.keySet()
            Assertions.assertThat(unknown.isEmpty(), "Unknown dimensions for ${stage.tool}: ${unknown}")
            return used
        }
        def unused = dimensions.keySet() - dimensionsByStage.flatten()
        Assertions.assertThat(unused.isEmpty(), "Unused dimensions: ${unused}")
        def selections = definition.selections
        Assertions.assertThat(selections && selections.every { it instanceof Map }, 'Expected a nonempty list of selection maps')
        selections.each { selection ->
            selection.each { dim, label ->
                Assertions.assertThat(dimensions[dim]?.containsKey(label) == true, "Unknown selection: ${dim}=${label}")
            }
        }
        return dimensionsByStage
    }

    private static boolean validLabel(value) {
        (value instanceof String && value.trim()) || value instanceof Number || value instanceof Boolean
    }

    private static void collectReferencedDimensions(value, Set used) {
        if (value instanceof DimensionReference) used.add(value.dimension)
        else if (value instanceof Map) value.values().each { collectReferencedDimensions(it, used) }
        else if (value instanceof List) value.each { collectReferencedDimensions(it, used) }
    }

    private PlannedStage planStage(StageDefinition stage, int position, List<PlannedRun> upstreamRuns, Set usedDimensions) {
        def runs = upstreamRuns.collectMany { parent ->
            expandChoices(parent.choices, usedDimensions).collect { choices ->
                def inputs = resolveInputs(stage.inputTemplate, choices, position)
                new PlannedRun(new RunKey(position, choices), parent.key, inputs, choices)
            }
        }
        return new PlannedStage(stage.id ?: stage.tool, stage.tool, runs)
    }

    private List expandChoices(Map inherited, Set usedDimensions) {
        def combinations = [inherited]
        for (dimension in usedDimensions - inherited.keySet()) {
            combinations = combinations.collectMany { choices ->
                definition.dimensions[dimension].keySet().collect { label -> choices + [(dimension): label] }
                    .findAll { candidate -> matchesSelectionSoFar(candidate) }
            }
        }
        return combinations
    }

    private boolean matchesSelectionSoFar(Map choices) {
        definition.selections.any { selection ->
            selection.every { dim, label -> !choices.containsKey(dim) || choices[dim] == label }
        }
    }

    private Object resolveInputs(template, Map choices, int position) {
        if (template instanceof List) return template.collect { resolveInputs(it, choices, position) }
        if (template instanceof Map) return template.collectEntries { k, v -> [(k): resolveInputs(v, choices, position)] }
        if (!(template instanceof DimensionReference)) return template

        def dim = template.dimension
        def value = definition.dimensions[dim][choices[dim]]
        for (field in template.fields) {
            Assertions.assertThat(value instanceof Map && value.containsKey(field), "Missing ${field} for ${dim}=${choices[dim]} at stage ${position}")
            value = value[field]
        }
        return value
    }
}
