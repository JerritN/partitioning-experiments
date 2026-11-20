/**
 * Selects rows whose unsigned 32-bit mask contains a given bit.  
 *
 * **Inputs**  
 * `context`: Execution context, passed through unchanged.  
 * `input_file`: Whitespace-delimited table.  
 * `bit`: Zero-based bit index for this input.  
 * `column`: 1-based position of the mask column.  
 *
 * **Outputs**  
 * `output`: Matching rows in input order (`output.txt`). Empty if no rows match.  
 */
process FILTER_ROWS_BY_BIT {
    input:
    tuple val(context), path(input_file, stageAs: 'input/*'), val(bit)
    val(column)

    output:
    tuple val(context), path('output.txt'), emit: output

    script:
    assert column instanceof Integer && column > 0 : "Expected a positive mask column"
    assert bit instanceof Integer && bit in 0..31 : "Expected bit index 0 through 31"

    def filter = new CommandBuilder('awk')
        .add('-v', "col=${column}", '-v', "bit=${1L << bit}")
        .add('$col !~ /^[0-9]+$/ || $col + 0 > 4294967295 { exit 1 } int($col / bit) % 2', input_file)
        .addUnwrapped('>')
        .add('output.txt')

    return new ScriptBuilder().addCommand(filter).build()
}
