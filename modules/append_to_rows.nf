

process APPEND_TO_ROWS {
    input:
    tuple val(context), path(input_file)
    val(value)

    output:
    tuple val(context), path("output.txt"),
        emit: output
    
    script:
    def command = new CommandBuilder('awk')
        .add("{print \$0, ${value}}")
        .add(input_file)
        .addUnwrapped('>')
        .add('output.txt')

    return new ScriptBuilder()
        .addCommand(command)
        .build()
}