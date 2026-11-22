
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

    /** Forward CLI options using snake_case keys and preserve each argument boundary. */
    CommandBuilder addOptions(Map options, Collection managed) {
        options.each { key, value ->
            assert key instanceof String && key ==~ /[A-Za-z0-9][A-Za-z0-9_]*/ : "Expected a CLI option name: ${key}"
            assert !managed.contains(key) : "Process manages option: ${key}"
            def flag = '--' + key.replace('_', '-')
            if (value == true) {
                add(flag)
            } else if (value != null && value != false) {
                assert value instanceof Number || value instanceof CharSequence : "Expected a scalar for ${flag}"
                add(flag, value)
            }
        }
        return this
    }

    CommandBuilder addUnwrapped(Object... parts) {
        if (parts.length == 0) return this

        assert parts.every { it != null } :
            "Command arguments must not be null"

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
