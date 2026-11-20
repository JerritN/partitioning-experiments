/**
 * Splits a whitespace-delimited table into one file per column, preserving row order.  
 *
 * **Inputs**  
 * `context`: Execution context, passed through unchanged.  
 * `input_file`: Table with a consistent number of fields per row.  
 *
 * **Outputs**  
 * `columns`: Column files named by their 1-based position (e.g. `1.txt`).  
 */
process SPLIT_COLUMNS {
    input:
    tuple val(context), path(input_file, stageAs: 'input/*')

    output:
    tuple val(context), path('columns/*.txt', arity: '1..*'), emit: columns

    script:
    def split = new CommandBuilder('awk')
        .add('NR == 1 { width = NF } NF != width { exit 1 } { for (i = 1; i <= NF; i++) print $i > ("columns/" i ".txt") }', input_file)

    return new ScriptBuilder()
        .addLine('mkdir -p columns')
        .addCommand(split)
        .build()
}
