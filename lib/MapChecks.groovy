class MapChecks {
    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message)
    }

    static void requireOnlyKeys(Object value, Collection allowedKeys, String location) {
        require(value instanceof Map, "Expected a map at ${location}")
        def unknown = value.keySet() - allowedKeys
        require(unknown.empty, "Unknown keys at ${location}: ${unknown}")
    }
}
