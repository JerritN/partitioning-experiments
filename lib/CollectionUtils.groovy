class CollectionUtils {

    /**
     * Converts a single value or collection into a list.
     * Returns an empty list for null.
     */
    static List asList(Object value) {
        if (value == null) return []
        if (value instanceof Collection) return value.toList()
        return [value]
    }

    /**
     * Finds a file with the given name in a collection of files.
     * Throws an exception if no match is found.
     */
    static Object findFile(Object files, String name) {
        def match = asList(files).find { it.name == name }
        assert match != null : "File not found: ${name}"
        return match
    }
}