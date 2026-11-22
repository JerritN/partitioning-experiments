package util

class CommandBuilder {
    private final Set<String> flags = new HashSet<>()
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

    /** Claim a long flag for the process, even when its optional input is absent. */
    CommandBuilder addFlagIf(boolean enabled, String flag, Object... values) {
        assert flags.add(flag) : "Flag already managed by command: ${flag}"
        if (enabled) add(flag, *values)
        return this
    }

    CommandBuilder addFlag(String flag, Object... values) {
        return addFlagIf(true, flag, *values)
    }

    /** Forward CLI options using snake_case keys and preserve each argument boundary. */
    CommandBuilder addOptions(Map options) {
        options.each { key, value ->
            assert key instanceof String && key ==~ /[A-Za-z0-9][A-Za-z0-9_]*/ : "Expected a CLI option name: ${key}"
            def flag = '--' + key.replace('_', '-')
            assert !flags.contains(flag) : "Process manages option: ${key}"
            if (value == true) {
                addFlag(flag)
            } else if (value != null && value != false) {
                assert value instanceof Number || value instanceof CharSequence : "Expected a scalar for ${flag}"
                addFlag(flag, value)
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
