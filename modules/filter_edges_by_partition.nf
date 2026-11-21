/**
 * Selects edge rows by the partition blocks of their endpoints.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `partition`: One nonnegative integer block ID per line. Line 1 corresponds to node 1.  
 * `edges`: Whitespace-delimited rows with two 1-based node IDs in the first two columns.  
 * `relation`: `between` for different blocks or `within` for the same block.  
 *
 * **Outputs**  
 * `output`: Matching rows in input order (`output.txt`). Extra columns and duplicates are preserved.  
 * Empty if no rows match.  
 */
process FILTER_EDGES_BY_PARTITION {
    input:
    tuple val(key), path(partition, stageAs: 'partition/input'), path(edges, stageAs: 'edges/input')
    val(relation)

    output:
    tuple val(key), path('output.txt'), emit: output

    script:
    assert relation in ['between', 'within'] : "Expected relation 'between' or 'within'"

    def program = '''
        function fail(message) {
            print FILENAME ":" FNR ": " message > "/dev/stderr"
            exit 1
        }
        FILENAME == ARGV[1] {
            if (NF != 1 || $1 !~ /^[0-9]+$/) fail("expected one nonnegative block ID")
            block[FNR] = $1 + 0
            nodes = FNR
            next
        }
        {
            if (NF < 2 || $1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/) fail("expected two node IDs")
            u = $1 + 0
            v = $2 + 0
            if (u < 1 || u > nodes || v < 1 || v > nodes) fail("node ID outside partition")
            if ((block[u] == block[v]) == within) print
        }
    '''.stripIndent()
    def command = new CommandBuilder('awk')
        .add('-v', "within=${relation == 'within' ? 1 : 0}", program, partition, edges)
        .addUnwrapped('>')
        .add('output.txt')

    return new ScriptBuilder().addCommand(command).build()
}
