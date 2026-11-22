class OptionChecks {
    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message)
    }

    static void checkMap(Object value, Collection allowed, String where) {
        require(value instanceof Map, "Expected a map at ${where}")
        def unknown = value.keySet() - allowed
        require(unknown.empty, "Unknown keys at ${where}: ${unknown}")
    }
}
