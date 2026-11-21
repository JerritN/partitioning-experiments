/**
 * Selects candidate edges whose endpoints belong to different partition blocks.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `partition`: One nonnegative integer block ID per line. Line 1 corresponds to node 1.  
 * `edges`: Whitespace-delimited rows with two 1-based node IDs in the first two columns.  
 *
 * **Outputs**  
 * `output`: Matching rows in input order (`cut_edges.txt`). Extra columns and duplicates are preserved.  
 * Empty if no edges cross between blocks.  
 * `count`: Number of matching rows (`count.txt`), including zero.  
 */
process FILTER_CUT_EDGES {
    input:
    tuple val(key), path(partition, stageAs: 'partition/input'), path(edges, stageAs: 'edges/input')

    output:
    tuple val(key), path('cut_edges.txt'), emit: output
    tuple val(key), path('count.txt'), emit: count

    script:
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
            if (block[u] != block[v]) {
                print
                count++
            }
        }
        END { printf "%.0f\\n", count + 0 > "count.txt" }
    '''.stripIndent()
    def command = new CommandBuilder('awk')
        .add(program, partition, edges)
        .addUnwrapped('>')
        .add('cut_edges.txt')

    return new ScriptBuilder().addCommand(command).build()
}
