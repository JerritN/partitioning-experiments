/** Pure planner. Keys depend on stage position and bound choice labels, including inherited choices. */
class LinearExperiment {
    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message)
    }

    private static boolean named(value) {
        value instanceof String && !value.trim().isEmpty()
    }

    private static boolean scalar(value) {
        named(value) || value instanceof Number || value instanceof Boolean
    }

    private static Map dimensionChoices(raw, String dimension) {
        if (raw instanceof Map && !raw.isEmpty() && raw.keySet().every { scalar(it) }) return raw
        require(raw instanceof List && !raw.empty && raw.every { scalar(it) },
            "Dimension ${dimension} needs named choices or a list of scalar values")
        require(raw.toSet().size() == raw.size(), "Duplicate choices in ${dimension}")
        raw.collectEntries { value -> [(value): value] }
    }

    private static List parseReference(value) {
        if (!(value instanceof String) || !value.contains('${')) return []
        def match = value =~ /^\$\{([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\}$/
        require(match.matches(), "Expected a whole-value dimension reference: ${value}")
        return match.group(1).tokenize('.')
    }

    private static Set referencedDimensions(value) {
        if (value instanceof Map) return referencedDimensions(value.values().toList())
        if (value instanceof List) return value.collectMany { referencedDimensions(it) } as Set
        return parseReference(value).take(1) as Set
    }

    private static Object resolveInputs(value, Map dimensions, Map choices, int position) {
        if (value instanceof Map) {
            return value.collectEntries { name, input -> [(name): resolveInputs(input, dimensions, choices, position)] }
        }
        if (value instanceof List) return value.collect { resolveInputs(it, dimensions, choices, position) }
        def path = parseReference(value)
        if (!path) return value
        return resolveReference(path, dimensions, choices, position)
    }

    private static Map normalizeDimensions(dimensionDefinitions) {
        require(dimensionDefinitions instanceof Map, 'dimensions must be a map')
        return dimensionDefinitions.collectEntries { dim, raw ->
            require(dim instanceof String && dim ==~ /[A-Za-z_][A-Za-z0-9_]*/, "Invalid dimension name: ${dim}")
            [(dim): dimensionChoices(raw, dim)]
        }
    }

    private static void checkSelections(selectors, Map dimensions) {
        require(selectors instanceof List && !selectors.empty, 'selections must be a nonempty list')
        selectors.each { selector ->
            require(selector instanceof Map, 'Each selection must be a map of dimension labels')
            selector.each { dim, label ->
                require(dimensions[dim]?.containsKey(label) == true, "Unknown selection: ${dim}=${label}")
            }
        }
    }

    private static Map prepareStage(definition, int position, Map dimensions) {
        def location = "stage ${position}"
        MapChecks.requireOnlyKeys(definition, ['id', 'tool', 'inputs', 'vary'], location)
        require(named(definition.tool), "${location} requires a tool")
        require(!definition.containsKey('id') || named(definition.id), "Invalid id at ${location}")
        def inputTemplate = definition.getOrDefault('inputs', [:])
        def vary = definition.getOrDefault('vary', [])
        require(inputTemplate instanceof Map && vary instanceof List, "${location} requires an inputs map and a vary list")
        def usedDimensions = new LinkedHashSet(vary)
        usedDimensions.addAll(referencedDimensions(inputTemplate))
        def unknown = usedDimensions - dimensions.keySet()
        require(unknown.isEmpty(), "Unknown dimensions at ${location}: ${unknown}")
        return [id: definition.id ?: definition.tool, tool: definition.tool,
                inputTemplate: inputTemplate, usedDimensions: usedDimensions]
    }

    private static boolean isCompatibleWithAnySelection(Map choices, List selections) {
        selections.any { selection ->
            selection.every { dim, label -> !choices.containsKey(dim) || choices[dim] == label }
        }
    }

    // Expand only dimensions first introduced here. Later stages inherit these choices.
    private static List expandChoices(Map inheritedChoices, Set usedDimensions, Map dimensions, List selections) {
        def combinations = [inheritedChoices]
        for (dim in usedDimensions - inheritedChoices.keySet()) {
            combinations = combinations.collectMany { choices ->
                dimensions[dim].keySet().collect { label -> choices + [(dim): label] }
                    .findAll { candidate -> isCompatibleWithAnySelection(candidate, selections) }
            }
        }
        return combinations
    }

    private static Object resolveReference(List path, Map dimensions, Map choices, int position) {
        def dim = path.first()
        def value = dimensions[dim][choices[dim]]
        path.tail().each { field ->
            require(value instanceof Map && value.containsKey(field),
                "Missing ${path.join('.')} for ${dim}=${choices[dim]} at stage ${position}")
            value = value[field]
        }
        value
    }

    private static Map planStage(stage, int position, List upstreamRuns, Map dimensions, List selections) {
        def runs = upstreamRuns.collectMany { upstreamRun ->
            def combinations = expandChoices(upstreamRun.choices, stage.usedDimensions, dimensions, selections)
            combinations.collect { choices ->
                def inputs = resolveInputs(stage.inputTemplate, dimensions, choices, position)
                [key: [stage: position, choices: choices], parentKey: upstreamRun.key, inputs: inputs, choices: choices]
            }
        }
        return [id: stage.id, tool: stage.tool, runs: runs]
    }

    static List plan(Map experiment) {
        MapChecks.requireOnlyKeys(experiment, ['name', 'dimensions', 'stages', 'selections'], 'experiment')
        require(named(experiment.name), 'Expected an experiment name')
        def dimensions = normalizeDimensions(experiment.getOrDefault('dimensions', [:]))
        def selections = experiment.getOrDefault('selections', [[:]])
        checkSelections(selections, dimensions)

        require(experiment.stages instanceof List && !experiment.stages.empty, 'Expected an ordered list of stages')
        def stageDefinitions = []
        experiment.stages.eachWithIndex { definition, index ->
            stageDefinitions << prepareStage(definition, index + 1, dimensions)
        }
        def explicitIds = experiment.stages*.id.findAll { it != null }
        require(explicitIds.size() == explicitIds.toSet().size(), "Duplicate explicit stage ids: ${explicitIds}")
        def unused = dimensions.keySet() - stageDefinitions.collectMany { it.usedDimensions }
        require(unused.isEmpty(), "Dimensions unused by inputs or vary: ${unused}")

        def plannedStages = []
        def upstreamRuns = [[key: null, choices: [:]]]
        stageDefinitions.eachWithIndex { definition, index ->
            def stage = planStage(definition, index + 1, upstreamRuns, dimensions, selections)
            plannedStages << stage
            upstreamRuns = stage.runs
        }
        return plannedStages
    }

    static void verifyStageSequence(List plannedStages, List expectedTools) {
        def actualTools = plannedStages*.tool
        require(actualTools == expectedTools, "Expected stages ${expectedTools}; received ${actualTools}")
    }
}
