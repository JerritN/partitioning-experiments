
process INDEX_ROWS {
    input:
    tuple val(context), path(input_file)
    val(start_index)

    output:
    tuple val(context), path('output.txt'),
        emit: output

    script:
    assert start_index instanceof Integer : "start_index must be an integer"

    def indexing = "NR + ${start_index} - 1"
    def command = new CommandBuilder('awk')
        .add("{print ${indexing}, \$0}", input_file)
        .addUnwrapped('>')
        .add('output.txt')
    return new ScriptBuilder()
        .addCommand(command)
        .build()
}