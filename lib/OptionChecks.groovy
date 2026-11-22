class OptionChecks {
    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message)
    }

    static void checkMap(Object value, Collection allowed, String where) {
        require(value instanceof Map, "Expected a map at ${where}")
        def unknown = value.keySet() - allowed
        require(unknown.empty, "Unknown keys at ${where}: ${unknown}")
    }

    private static boolean label(Object value) {
        value instanceof String && !value.trim().isEmpty() && !value.find(/[\r\n\t]/)
    }

    static void checkOptions(Map opts, Map schema, String where) {
        checkMap(opts, schema.values().collectMany { it.tokenize() }, where)
        schema.each { type, names ->
            opts.subMap(names.tokenize()).each { key, value ->
                boolean valid
                switch (type) {
                    case 'integer': valid = value instanceof Integer || value instanceof Long; break
                    case 'number': valid = value instanceof Number; break
                    case 'string': valid = label(value); break
                    case 'flag': valid = value instanceof Boolean; break
                    case 'stringOrNumbers': valid = label(value) || (value instanceof List && !value.empty && value.every { it instanceof Number }); break
                    default: throw new IllegalArgumentException("Unknown option type: ${type}")
                }
                require(valid, "Invalid ${type} option at ${where}.${key}: ${value}")
            }
        }
    }
}
