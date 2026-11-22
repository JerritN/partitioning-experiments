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
        checkSelectionLabels()
        def explicitIds = new HashSet()
        def unusedDimensions = new LinkedHashSet(definition.dimensions.keySet())
        def stages = []
        def upstreamRuns = [new PlannedRun(null, null, [:], [:])]
        definition.stages.eachWithIndex { stage, index ->
            if (stage.id != null)
                Assertions.assertThat(explicitIds.add(stage.id), "Duplicate stage id: ${stage.id}")
            def usedDimensions = new LinkedHashSet(stage.vary)
            collectReferencedDimensions(stage.inputTemplate, usedDimensions)
            def unknown = usedDimensions - definition.dimensions.keySet()
            Assertions.assertThat(unknown.isEmpty(), "Unknown dimensions for ${stage.tool}: ${unknown}")
            unusedDimensions.removeAll(usedDimensions)
            def planned = planStage(stage, index + 1, upstreamRuns, usedDimensions)
            stages << planned
            upstreamRuns = planned.runs
        }
        Assertions.assertThat(unusedDimensions.isEmpty(), "Unused dimensions: ${unusedDimensions}")
        return new Experiment(definition.name, stages)
    }

    private void checkSelectionLabels() {
        definition.selections.each { selection ->
            selection.each { dim, label ->
                Assertions.assertThat(definition.dimensions[dim]?.containsKey(label) == true, "Unknown selection: ${dim}=${label}")
            }
        }
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
