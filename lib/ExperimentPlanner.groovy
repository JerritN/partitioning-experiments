class ExperimentPlanner {
    private final ExperimentDefinition definition

    private ExperimentPlanner(ExperimentDefinition definition) {
        this.definition = definition
    }

    static Experiment plan(ExperimentDefinition definition) {
        return new ExperimentPlanner(definition).expandStages()
    }

    private Experiment expandStages() {
        def stages = []
        def upstreamRuns = [new PlannedRun(null, null, [:], [:])]
        definition.stages.eachWithIndex { stage, index ->
            def planned = planStage(stage, index + 1, upstreamRuns)
            stages << planned
            upstreamRuns = planned.runs
        }
        return new Experiment(definition.name, stages)
    }

    private PlannedStage planStage(StageDefinition stage, int position, List<PlannedRun> upstreamRuns) {
        def runs = upstreamRuns.collectMany { parent ->
            expandChoices(parent.choices, stage.usedDimensions).collect { choices ->
                def inputs = resolveInputs(stage.inputTemplate, choices, position)
                new PlannedRun([stage: position, choices: choices], parent.key, inputs, choices)
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
            if (!(value instanceof Map) || !value.containsKey(field))
                throw new IllegalArgumentException("Missing ${field} for ${dim}=${choices[dim]} at stage ${position}")
            value = value[field]
        }
        return value
    }
}
