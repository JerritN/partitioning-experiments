/**
 * Filters a graph using PUNCH and generates a contracted fragment graph.  
 *
 * **Inputs**  
 * `context`: Execution context, passed through unchanged.  
 * `graph`: Input graph in DIMACS (`.gr`) or METIS format.  
 * `opts`: Dictionary of filtering parameters.  
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
 * All three output files are always generated.  
 *
 * **Outputs**  
 * `graph`: Contracted fragment graph in METIS format (`fragments.graph`).  
 * `mapping`: Original vertex-to-fragment mapping (`fragment_mapping.txt`).  
 * `kept_edges`: List of retained edges (`kept_edges.txt`).  
 * `log`: Combined stdout and stderr (`punch.log`).  
 * All outputs retain the original `context`.  
 *
 * **Configuration**  
 * `params.tools.punch_filter`: Path to the PUNCH executable.  
 */

process PUNCH_FILTER {
    label 'filtering'

    input:
    tuple val(context), path(graph), val(opts)

    output:
    tuple val(context), path('fragments.graph'),
        emit: graph

    tuple val(context), path('fragment_mapping.txt'),
        emit: mapping

    tuple val(context), path('kept_edges.txt'),
        emit: kept_edges

    tuple val(context), path('punch.log'),
        emit: log

    script:
    assert params.tools.punch_filter != null 
        : "Missing configuration: params.tools.punch_filter must be set to the path of the PUNCH executable"

    assert opts.U != null 
        : "PUNCH requires parameter U"

    def command = [
        "\"${params.tools.punch_filter}\"",
        "--graph \"${graph}\"",
        "--U ${opts.U}",
        '--dump-fragment-graph fragments.graph',
        '--dump-partition fragment_mapping.txt',
        '--dump-kept-edges kept_edges.txt',
    ]

    if (opts.alpha != null)     command << "--alpha ${opts.alpha}"
    if (opts.f != null)         command << "--f ${opts.f}"
    if (opts.coverage != null)  command << "--coverage ${opts.coverage}"
    if (opts.cut_side != null)  command << "--cut-side ${opts.cut_side}"
    if (opts.tau != null)       command << "--tau ${opts.tau}"

    if (opts.arc_weights == true)   command << '--arc-weights'
    if (opts.verbose == true)       command << '--verbose'

    command << "> punch.log 2>&1"

    return command.join(' \\\n')
}