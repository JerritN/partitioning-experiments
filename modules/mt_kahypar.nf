

/**
 * Partitions a graph or hypergraph using Mt-KaHyPar.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `executable`: Mt-KaHyPar executable, prebuilt or supplied by a build process.  
 * `graph`: Input graph or hypergraph file.  
 * `initial_partition`: Optional initial partition or fragment mapping (`[]` if omitted).  
 * `edge_metadata`: Optional edge metadata file (`[]` if omitted).
 * `opts`: Dictionary of partitioning parameters.  
 *
 * Scalar snake_case options are forwarded as long CLI flags. Boolean true enables a switch.  
 *
 * **Required parameters (`opts`)**  
 * `blocks`: Number of partition blocks.  
 * `epsilon`: Allowed imbalance.  
 * `objective`: `cut`, `km1`, `soed`, or `steiner_tree`.  
 * `preset_type`: Mt-KaHyPar preset.  
 *
 * **Optional parameters (`opts`)**  
 * `threads`: Number of CPU threads (default: 1).  
 * `seed`: Random seed.  
 * `file_format`: `metis` or `hmetis`.  
 * `num_vcycles`: Number of V-cycles.  
 * `initial_partition_relax_on_stall`: Relax fragment restrictions on stall.  
 * `initial_partition_vcycle_fragments`: Restrict coarsening during V-cycles.  
 * `edge_metadata_type`: Type of edge metadata.
 * `c_rating_edge_metadata`: rating policy for edge metadata.
 *
 * **Optional switches (`opts`)**  
 * `allow_empty_blocks`, `quiet`, `verbose`,  
 * `enable_progress_bar`, `show_detailed_timings`.  
 *
 * Omitted optional parameters use the executable's defaults.  
 * Partition file generation is always enabled.  
 *
 * **Outputs**  
 * `partition`: Vertex-to-block mapping (`partition.txt`).  
 * `log`: Combined stdout and stderr (`mt_kahypar.log`).  
 * `result`: Machine-readable RESULT line (`result.txt`).  
 * All outputs retain the original `key`.  
 */

process MT_KAHYPAR {
    label 'partitioning'
    cache params.get('cache_mt_kahypar', true)

    cpus { opts.threads ?: 1 }

    input:
    tuple val(key), 
        path(executable),
        path(graph), 
        path(initial_partition),
        path(edge_metadata),
        val(opts)

    output:
    tuple val(key), path('partition.txt'),
        emit: partition

    tuple val(key), path('mt_kahypar.log'),
        emit: log

    tuple val(key), path('result.txt'),
        emit: result

    script:

    def command = new util.CommandBuilder("./${executable}")
        .addFlag("--hypergraph", graph)
        .addFlag("--threads", task.cpus)
        .addFlag("--sp-process")
        .addFlag("--write-partition-file")
        .addFlag("--partition-output-folder", "partitions")
        .addFlagIf(initial_partition as boolean, "--initial-partition", initial_partition)
        .addFlagIf(edge_metadata as boolean, "--edge-metadata", edge_metadata)
    // Explicit boolean-valued options
    def booleanValues = [
        initial_partition_relax_on_stall: '--initial-partition-relax-on-stall',
        initial_partition_vcycle_fragments: '--initial-partition-vcycle-fragments'
    ]

    booleanValues.each { option, flag ->
        if (opts[option] != null) {
            command.add("${flag}=${opts[option] ? 1 : 0}")
        }
    }

    def handled = booleanValues.keySet() + ['threads']
    command.addOptions(opts.findAll { name, _value -> !handled.contains(name) })

    def script = new util.ScriptBuilder()
        .addLine('mkdir -p partitions')
        .addCommand(command, 'mt_kahypar.log', true)
        
        .addLine("awk '/^RESULT / { print; count++ } END { exit (count != 1) }' mt_kahypar.log > result.txt || {")
        .addLine('    echo "Expected exactly one RESULT line in mt_kahypar.log" >&2')
        .addLine('    exit 1')
        .addLine('}')

        .addLine('shopt -s nullglob')
        .addLine('files=(partitions/*)')

        // Check that exactly one partition file was generated
        .addLine('if [ "${#files[@]}" -ne 1 ] || [ ! -f "${files[0]}" ]; then')
        .addLine('    echo "Expected exactly one partition file" >&2')
        .addLine('    exit 1')
        .addLine('fi')

        .addLine('mv "${files[0]}" partition.txt')

    return script.build()
}
