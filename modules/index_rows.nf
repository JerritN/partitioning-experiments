/**
 * Prepends a sequential index to every row.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `input_file`: Input text file.  
 * `start_index`: Integer index assigned to the first row.  
 *
 * **Outputs**  
 * `output`: Transformed file paired with the original key.  
 */
process INDEX_ROWS {
    input:
    tuple val(key), path(input_file)
    val(start_index)

    output:
    tuple val(key), path('output.txt'),
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