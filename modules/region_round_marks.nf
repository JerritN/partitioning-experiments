/**
 * Converts RegionFilter outputs to Streetviz markings for one round.  
 *
 * **Inputs**  
 * `context`: Execution context, passed through unchanged.  
 * `round`: Zero-based round index (0 through 30).  
 * `regions`: Region IDs in original vertex order, one column per round.  
 * `cut_edges`: Retained edges with 1-based endpoints, round mask, and boundary flag.  
 *
 * **Outputs**  
 * `marks`: Context, round, edge marks, and node marks. Retained edges detected in this round use group 0.  
 * Fallback-only edges have no round assignment.  
 */
process REGION_ROUND_MARKS {
    label 'visualization'

    input:
    tuple val(context), val(round), path(regions), path(cut_edges)

    output:
    tuple val(context), val(round), path('edge_marks.txt'), path('node_marks.txt'),
        emit: marks

    script:
    assert round >= 0 && round < 31 : "Expected a RegionFilter round between 0 and 30"

    def nodes = new CommandBuilder('awk')
        .add('-v', "col=${round + 1}", 'NF < col { exit 1 } { print NR, $col }', regions)
        .addUnwrapped('>')
        .add('node_marks.txt')

    def edges = new CommandBuilder('awk')
        .add('-v', "bit=${1L << round}", 'int($3 / bit) % 2 { print $1, $2, 0 }', cut_edges)
        .addUnwrapped('>')
        .add('edge_marks.txt')

    return new ScriptBuilder()
        .addCommand(nodes)
        .addCommand(edges)
        .build()
}
