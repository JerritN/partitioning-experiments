package util

class Assertions {
    static void assertThat(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message)
    }

    static void assertOnlyKeys(Object value, Collection allowedKeys, String location) {
        assertThat(value instanceof Map, "Expected a map at ${location}")
        def unknown = value.keySet() - allowedKeys
        assertThat(unknown.empty, "Unknown keys at ${location}: ${unknown}")
    }
}
