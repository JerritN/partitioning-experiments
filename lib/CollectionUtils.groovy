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
}