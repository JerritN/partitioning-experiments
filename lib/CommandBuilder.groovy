
class CommandBuilder {
    private List<String> commandParts = []

    /**
     * Initializes a command with the given executable.
     */
    CommandBuilder(String command) {
        commandParts << ShellUtils.quote(command)
    }

    /**
     * Adds one or more shell arguments.
     */
    CommandBuilder add(Object... parts) {
        if (parts.length == 0) return this

        assert parts.every { it != null } :
            "Command arguments must not be null"

        commandParts << parts.collect {
            ShellUtils.quote(it)
        }.join(' ')

        return this
    }

    CommandBuilder addAll(Collection parts) {
        return add(*parts)
    }

    CommandBuilder addUnwrapped(Object... parts) {
        if (parts.length == 0) return this

        assert parts.every { it != null } :
            "Command arguments must not be null"

        def segments = parts.flatten().collect { it.toString() }

        commandParts << parts.collect {
            it.toString()
        }.join(' ')

        return this
    }

    /**
     * Conditionally adds shell arguments.
     */
    CommandBuilder addIf(boolean condition, Object... parts) {
        if (condition) {
            add(*parts)
        }
        return this
    }

    /**
     * Builds the quoted shell command.
     */
    String build(boolean multiline = false) {
        return commandParts.join(multiline ? ' \\\n' : ' ')
    }
}
