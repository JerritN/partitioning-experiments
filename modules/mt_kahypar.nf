

/**
 * Partitions a graph or hypergraph using Mt-KaHyPar.  
 *
 * **Inputs**  
 * `context`: Execution context, passed through unchanged.  
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
 *
 * **Configuration**  
 * `params.tools.mt_kahypar`: Path to the executable.  
 */

process MT_KAHYPAR {
    label 'partitioning'

    cpus { opts.threads ?: 1 }

    input:
    tuple val(context), 
        path(graph), 
        path(initial_partition),
        val(opts)

    output:
    tuple val(context), path('partition.txt'),
        emit: partition

    tuple val(context), path('mt_kahypar.log'),
        emit: log

    script:
    // Required value arguments
    def required = [
        blocks: '--blocks',
        epsilon: '--epsilon',
        objective: '--objective',
        preset_type: '--preset-type'
    ]

    // Optional value arguments
    def optional = [
        seed: '--seed',
        file_format: '--file-format',
        num_vcycles: '--num-vcycles'
    ]

    // Boolean switches
    def switches = [
        allow_empty_blocks: '--allow-empty-blocks',
        quiet: '--quiet',
        verbose: '--verbose',
        enable_progress_bar: '--enable-progress-bar',
        show_detailed_timings: '--show-detailed-timings'
    ]

    // Explicit boolean-valued options
    def booleanValues = [
        initial_partition_relax_on_stall: '--initial-partition-relax-on-stall',
        initial_partition_vcycle_fragments: '--initial-partition-vcycle-fragments'
    ]

    assert params.tools.mt_kahypar != null 
        : "Missing configuration: params.tools.mt_kahypar must be set to the path of the Mt-KaHyPar executable"

    required.each { key, _flag ->
        assert opts[key] != null 
            : "Mt-KaHyPar requires parameter ${key}"
    }

    def command = [
        "\"${params.tools.mt_kahypar}\"",
        "--hypergraph \"${graph}\"",
        "--threads ${task.cpus}"
    ]

    required.each { key, flag ->
        command << "${flag} ${opts[key]}"
    }

    if (initial_partition) command << "--initial-partition \"${initial_partition}\""

    optional.each { key, flag ->
        if (opts[key] != null) {
            command << "${flag} ${opts[key]}"
        }
    }

    switches.each { key, flag ->
        if (opts[key] == true) {
            command << flag
        }
    }

    booleanValues.each { key, flag ->
        if (opts[key] != null) {
            command << "${flag}=${opts[key] ? 1 : 0}"
        }
    }

    // Always generate a partition file
    command << '--write-partition-file'
    command << '--partition-output-folder partitions'

    command << "> mt_kahypar.log 2>&1"

    def command_line = command.join(' \\\n')

    """
mkdir -p partitions

${command_line}

shopt -s nullglob
files=(partitions/*)

if [ "\${#files[@]}" -ne 1 ] || [ ! -f "\${files[0]}" ]; then
    echo "Expected exactly one partition file" >&2
    exit 1
fi

mv "\${files[0]}" partition.txt
    """
}
