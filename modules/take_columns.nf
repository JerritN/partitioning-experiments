/**
 * Selects whitespace-separated columns in the requested order.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `input_file`: Input text file.  
 * `columns`: One-based column index or list of indices.  
 *
 * **Outputs**  
 * `output`: Transformed file paired with the original key.  
 */
process TAKE_COLUMNS {
    input:
    tuple val(key), path(input_file, stageAs: 'input/*')
    val(columns)

    output:
    tuple val(key), path('output.txt'),
        emit: output

    script:
    def columnsList = util.CollectionUtils.asList(columns)

    assert columnsList.size() > 0 : "At least one column must be specified"
    assert columnsList.every { column -> column instanceof Integer } : "All columns must be integers"
    assert columnsList.every { column -> column > 0 } : "All columns must be positive integers"

    def command = new util.CommandBuilder('awk')
        .add("{print ${columnsList.collect { column -> "\$${column}" }.join(', ')}}")
        .add(input_file)
        .addUnwrapped('>')
        .add('output.txt')

    return new util.ScriptBuilder()
        .addCommand(command)
        .build()
}
