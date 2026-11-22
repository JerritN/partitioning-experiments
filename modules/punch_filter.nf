/**
 * Filters a graph using PUNCH and generates a contracted fragment graph.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `executable`: Path to the PUNCH executable, either prebuilt or produced by a build process.  
 * `graph`: Input graph in DIMACS (`.gr`) or METIS format.  
 * `opts`: Map of filtering parameters.  
 *
 * **Required parameters (`opts`)**  
 * `U`: Maximum fragment size.  
 *
 * **Optional parameters (`opts`)**  
 * `alpha`: Natural cut parameter (default: 1.0).  
 * `f`: Filtering parameter (default: 10).  
 * `coverage`: Natural cut coverage (default: 2).  
 * `cut_side`: `source`, `sink`, or `both` (default: source).  
 * `tau`: Tiny cut threshold (default: 5).  
 *
 * **Optional switches (`opts`)**  
 * `arc_weights`: Use DIMACS arc weights (ignored for METIS input).  
 * `verbose`: Enable detailed filtering output.  
 *
 * Omitted optional parameters use the executable's defaults.  
 * All four output files are always generated.  
 *
 * **Outputs**  
 * `graph`: Contracted fragment graph in METIS format (`fragments.graph`).  
 * `mapping`: Original vertex-to-fragment mapping (`fragment_mapping.txt`).  
 * `kept_edges`: List of retained edges (`kept_edges.txt`).  
 * `log`: Combined stdout and stderr (`punch.log`).  
 * All outputs retain the original `key`.  
 *
 * **Requirements**  
 * The supplied executable must be compatible with the execution environment.  
 * Nextflow stages the executable and input graph into the task directory.  
 */
process PUNCH_FILTER {
    label 'filtering'
    cache params.get('cache_punch_filter', true)

    input:
    tuple val(key),
        path(executable),
        path(graph),
        val(opts)

    output:
    tuple val(key), path('fragments.graph'),
        emit: graph

    tuple val(key), path('fragment_mapping.txt'),
        emit: mapping

    tuple val(key), path('kept_edges.txt'),
        emit: kept_edges

    tuple val(key), path('punch.log'),
        emit: log

    script:
    assert opts.U != null 
        : "PUNCH requires parameter U"

    def command = new util.CommandBuilder("./${executable}")
        .add('--graph', graph)
        .add('--U', opts.U)
        .add('--dump-fragment-graph', 'fragments.graph')
        .add('--dump-partition', 'fragment_mapping.txt')
        .add('--dump-kept-edges', 'kept_edges.txt')
        .addIf(opts.alpha != null, '--alpha', opts.alpha)
        .addIf(opts.f != null, '--f', opts.f)
        .addIf(opts.coverage != null, '--coverage', opts.coverage)
        .addIf(opts.cut_side != null, '--cut-side', opts.cut_side)
        .addIf(opts.tau != null, '--tau', opts.tau)
        .addIf(opts.arc_weights == true, '--arc-weights')
        .addIf(opts.verbose == true, '--verbose')

    def script = new util.ScriptBuilder()
        .addCommand(command, 'punch.log', true)

    return script.build()
}