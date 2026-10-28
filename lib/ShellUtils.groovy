
class ShellUtils {

    /**
     * Quotes a value as a single POSIX shell argument.
     */
    static String quote(Object value) {
        return "'" + value.toString().replace("'", "'\"'\"'") + "'"
    }
}
