

/**
 * Partitions a graph or hypergraph using Mt-KaHyPar.  
 *
 * **Inputs**  
 * `context`: Execution context, passed through unchanged.  
 * `executable`: Mt-KaHyPar executable, prebuilt or supplied by a build process.  
 * `graph`: Input graph or hypergraph file.  
 * `initial_partition`: Optional initial partition or fragment mapping (`[]` if omitted).  
 * `opts`: Dictionary of partitioning parameters.  
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
 * Both outputs retain the original `context`.  
 */

process MT_KAHYPAR {
    label 'partitioning'

    cpus { opts.threads ?: 1 }

    input:
    tuple val(context), 
        path(executable),
        path(graph), 
        path(initial_partition),
        val(opts)

    output:
    tuple val(context), path('partition.txt'),
        emit: partition

    tuple val(context), path('mt_kahypar.log'),
        emit: log

    script:

    assert opts.blocks != null : "Mt-KaHyPar requires blocks"
    assert opts.epsilon != null : "Mt-KaHyPar requires epsilon"
    assert opts.objective != null : "Mt-KaHyPar requires objective"
    assert opts.preset_type != null : "Mt-KaHyPar requires preset_type"

    def command = new CommandBuilder("./${executable}")
        .add("--hypergraph", graph)
        .add("--threads", task.cpus)
        .add("--blocks", opts.blocks)
        .add("--epsilon", opts.epsilon)
        .add("--objective", opts.objective)
        .add("--preset-type", opts.preset_type)
        .add("--write-partition-file")
        .add("--partition-output-folder", "partitions")
        .addIf(initial_partition, "--initial-partition", initial_partition)
        .addIf(opts.seed != null, "--seed", opts.seed)
        .addIf(opts.file_format != null, "--file-format", opts.file_format)
        .addIf(opts.num_vcycles != null, "--num-vcycles", opts.num_vcycles)
        .addIf(opts.allow_empty_blocks == true, "--allow-empty-blocks")
        .addIf(opts.quiet == true, "--quiet")
        .addIf(opts.verbose == true, "--verbose")
        .addIf(opts.enable_progress_bar == true, "--enable-progress-bar")
        .addIf(opts.show_detailed_timings == true, "--show-detailed-timings")

    // Explicit boolean-valued options
    def booleanValues = [
        initial_partition_relax_on_stall: '--initial-partition-relax-on-stall',
        initial_partition_vcycle_fragments: '--initial-partition-vcycle-fragments'
    ]

    booleanValues.each { key, flag ->
        if (opts[key] != null) {
            command.add("${flag}=${opts[key] ? 1 : 0}")
        }
    }

    def script = new ScriptBuilder()
        .addLine('mkdir -p partitions')
        .addCommand(command, 'mt_kahypar.log', true)
        .addLine('shopt -s nullglob')
        .addLine('files=(partitions/*)')
        .addLine('if [ "${#files[@]}" -ne 1 ] || [ ! -f "${files[0]}" ]; then')
        .addLine('    echo "Expected exactly one partition file" >&2')
        .addLine('    exit 1')
        .addLine('fi')
        .addLine('mv "${files[0]}" partition.txt')

    return script.build()
}
