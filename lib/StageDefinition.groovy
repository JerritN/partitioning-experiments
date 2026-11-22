class StageDefinition {
    final String tool
    final String id
    final Map inputTemplate
    final Set<String> usedDimensions

    StageDefinition(String tool, Map inputTemplate = [:], List vary = [], String id = null) {
        if (!tool?.trim() || (id != null && !id.trim()))
            throw new IllegalArgumentException('Expected a tool name and a nonempty optional stage id')
        this.tool = tool
        this.id = id
        this.inputTemplate = inputTemplate.asImmutable()
        def used = new LinkedHashSet(vary)
        collectDimensions(inputTemplate, used)
        this.usedDimensions = used.asImmutable()
    }

    private static void collectDimensions(value, Set used) {
        if (value instanceof DimensionReference) used.add(value.dimension)
        else if (value instanceof Map) value.values().each { collectDimensions(it, used) }
        else if (value instanceof List) value.each { collectDimensions(it, used) }
    }
}
