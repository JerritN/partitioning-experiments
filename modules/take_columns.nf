
process TAKE_COLUMNS {
    input:
    tuple val(context), path(input_file)
    val(columns)

    output:
    tuple val(context), path('output.txt'),
        emit: output

    script:
    def columnsList = CollectionUtils.toList(columns)

    assert columnsList.size() > 0 : "At least one column must be specified"
    assert columnsList.every { column -> column instanceof Integer } : "All columns must be integers"
    assert columnsList.every { column -> column > 0 } : "All columns must be positive integers"

    def command = new CommandBuilder('awk')
        .add("{print ${columnsList.collect { column -> "\$${column}" }.join(', ')}}")
        .add(input_file)
        .addUnwrapped('>')
        .add('output.txt')

    return new ScriptBuilder()
        .addCommand(command)
        .build()
}