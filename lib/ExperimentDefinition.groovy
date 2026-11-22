class ExperimentDefinition {
    final String name
    final Map dimensions
    final List<StageDefinition> stages
    final List<Map> selections

    ExperimentDefinition(String name, Map dimensions, List<StageDefinition> stages, List<Map> selections = [[:]]) {
        require(name?.trim() as boolean, 'Expected an experiment name')
        require(stages && stages.every { it instanceof StageDefinition }, 'Expected at least one stage definition')
        dimensions.each { dimension, choices ->
            require(dimension instanceof String && dimension ==~ /[A-Za-z_][A-Za-z0-9_]*/, "Invalid dimension name: ${dimension}")
            require(choices instanceof Map && !choices.isEmpty() && choices.keySet().every { validLabel(it) },
                "Expected named choices for dimension ${dimension}")
        }
        def explicitIds = stages*.id.findAll { it != null }
        require(explicitIds.toSet().size() == explicitIds.size(), "Duplicate stage ids: ${explicitIds}")
        def used = stages.collectMany { it.usedDimensions } as Set
        require((used - dimensions.keySet()).empty, "Unknown dimensions: ${used - dimensions.keySet()}")
        require((dimensions.keySet() - used).empty, "Unused dimensions: ${dimensions.keySet() - used}")
        require(selections && selections.every { it instanceof Map }, 'Expected a nonempty list of selection maps')
        selections.each { selection ->
            selection.each { dim, label ->
                require(dimensions[dim]?.containsKey(label) == true, "Unknown selection: ${dim}=${label}")
            }
        }
        this.name = name
        this.dimensions = dimensions.asImmutable()
        this.stages = stages.asImmutable()
        this.selections = selections.asImmutable()
    }

    private static boolean validLabel(value) {
        (value instanceof String && value.trim()) || value instanceof Number || value instanceof Boolean
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message)
    }
}
