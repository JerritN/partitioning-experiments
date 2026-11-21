/**
 * Splits edge rows by the partition blocks of their endpoints.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `partition`: One nonnegative integer block ID per line. Line 1 corresponds to node 1.  
 * `edges`: Whitespace-delimited rows with two 1-based node IDs in the first two columns.  
 *
 * **Outputs**  
 * `between`: Rows whose endpoints belong to different blocks (`between.txt`).  
 * `within`: Rows whose endpoints belong to the same block (`within.txt`).  
 * Each output retains the key, input order, extra columns and duplicates. Either file may be empty.  
 */
process SPLIT_EDGES_BY_PARTITION {
    input:
    tuple val(key), path(partition, stageAs: 'partition/input'), path(edges, stageAs: 'edges/input')

    output:
    tuple val(key), path('between.txt'), emit: between
    tuple val(key), path('within.txt'), emit: within

    script:
    def program = '''
        BEGIN {
            printf "" > "between.txt"
            printf "" > "within.txt"
        }
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
            if (block[u] == block[v]) print > "within.txt"
            else print > "between.txt"
        }
    '''.stripIndent()
    def command = new CommandBuilder('awk')
        .add(program, partition, edges)

    return new ScriptBuilder().addCommand(command).build()
}
