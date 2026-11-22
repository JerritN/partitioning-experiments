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

    // Apply the same reference syntax when discovering dependencies and resolving options.
    private static Object references(value, Closure resolve) {
        if (value instanceof Map) return value.collectEntries { k, v -> [(k): references(v, resolve)] }
        if (value instanceof List) return value.collect { references(it, resolve) }
        if (!(value instanceof String) || !value.contains('${')) return value
        def match = value =~ /^\$\{([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\}$/
        require(match.matches(), "Expected a whole-value dimension reference: ${value}")
        resolve(match.group(1).tokenize('.'))
    }

    static Map dimensions(rawDimensions) {
        require(rawDimensions instanceof Map, 'dimensions must be a map')
        return rawDimensions.collectEntries { dim, raw ->
            require(dim instanceof String && dim ==~ /[A-Za-z_][A-Za-z0-9_]*/, "Invalid dimension name: ${dim}")
            [(dim): dimensionChoices(raw, dim)]
        }
    }

    static void checkSelections(selectors, Map dimensions) {
        require(selectors instanceof List && !selectors.empty, 'selections must be a nonempty list')
        selectors.each { selector ->
            require(selector instanceof Map, 'Each selection must be a map of dimension labels')
            selector.each { dim, label ->
                require(dimensions[dim]?.containsKey(label) == true, "Unknown selection: ${dim}=${label}")
            }
        }
    }

    static List stages(rawStages, Map dimensions) {
        require(rawStages instanceof List && !rawStages.empty, 'Expected an ordered list of stages')
        def batches = []
        def used = [] as Set
        def ids = [] as Set
        rawStages.eachWithIndex { stage, index ->
            def where = "stage ${index + 1}"
            OptionChecks.checkMap(stage, ['id','tool','options','vary'], where)
            require(named(stage.tool), "${where} requires a tool")
            if (stage.containsKey('id')) {
                require(named(stage.id) && ids.add(stage.id), "Invalid or duplicate stage id at ${where}: ${stage.id}")
            }
            def options = stage.getOrDefault('options', [:])
            def vary = stage.getOrDefault('vary', [])
            require(options instanceof Map && vary instanceof List, "${where} requires an options map and a vary list")
            def dependencies = new LinkedHashSet(vary)
            references(options) { path -> dependencies.add(path.first()) }
            dependencies.each { dim -> require(dimensions.containsKey(dim), "Unknown dimension ${dim} at ${where}") }
            used.addAll(dependencies)
            batches << [id: stage.id ?: stage.tool, tool: stage.tool, options: options, dependencies: dependencies]
        }
        def unused = dimensions.keySet() - used
        require(unused.isEmpty(), "Dimensions unused by options or vary: ${unused}")
        return batches
    }

    private static boolean canMatch(Map choices, List selections) {
        selections.any { selection ->
            selection.every { dim, label -> !choices.containsKey(dim) || choices[dim] == label }
        }
    }

    // Expand only dimensions first introduced here. Later stages inherit these choices.
    private static List bindings(Map inherited, Set dependencies, Map dimensions, List selections) {
        def rows = [inherited]
        for (dim in dependencies - inherited.keySet()) {
            rows = rows.collectMany { row ->
                dimensions[dim].keySet().collect { label -> row + [(dim): label] }
                    .findAll { choices -> canMatch(choices, selections) }
            }
        }
        return rows
    }

    private static Object resolve(List path, Map dimensions, Map choices, int position) {
        def dim = path.first()
        def value = dimensions[dim][choices[dim]]
        path.tail().each { field ->
            require(value instanceof Map && value.containsKey(field),
                "Missing ${path.join('.')} for ${dim}=${choices[dim]} at stage ${position}")
            value = value[field]
        }
        value
    }

    static List plan(Map dimensions, List stages, List selections) {
        def parents = [[key: null, choices: [:]]]
        def batches = []
        stages.eachWithIndex { stage, index ->
            int position = index + 1
            def requests = parents.collectMany { parent ->
                bindings(parent.choices, stage.dependencies, dimensions, selections).collect { choices ->
                    def options = references(stage.options) { path -> resolve(path, dimensions, choices, position) }
                    [key: [stage: position, choices: choices], parentKey: parent.key, options: options, choices: choices]
                }
            }
            batches << [id: stage.id, tool: stage.tool, requests: requests]
            parents = requests
        }
        return batches
    }
}
