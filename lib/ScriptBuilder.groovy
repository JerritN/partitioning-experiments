
class ScriptBuilder {
    private List<String> commands = []

    /**
     * Adds arbitrary shell code.
     */
    ScriptBuilder addLine(String line) {
        commands << line
        return this
    }

    /**
    * Adds a constructed shell command, optionally redirecting
    * both stdout and stderr to a file.
    */
    ScriptBuilder addCommand(
        CommandBuilder command,
        String redirectOutput = null,
        boolean multiline = false
    ) {
        def line = command.build(multiline)

        if (redirectOutput != null) {
            if (multiline) {
                line += " \\\n"
            }
            line += " > ${ShellUtils.quote(redirectOutput)} 2>&1"
        }

        commands << line
        return this
    }

    /**
     * Builds the complete shell script.
     */
    String build() {
        return commands.join('\n')
    }
}
