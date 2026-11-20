/**
 * Appends a value to every row.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `input_file`: Input text file.  
 * `value`: Value to append to each row.  
 *
 * **Outputs**  
 * `output`: Transformed file paired with the original key.  
 */
process APPEND_TO_ROWS {
    input:
    tuple val(key), path(input_file, stageAs: 'input/*')
    val(value)

    output:
    tuple val(key), path("output.txt"),
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
