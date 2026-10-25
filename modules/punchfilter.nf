
/**
 * Executes PUNCH graph filtering on a DIMACS or METIS graph.  
 *
 * **Inputs**  
 * `context`: Execution context, passed through unchanged.  
 * `graph`: Input graph file.  
 * `opts`: Map of filtering parameters.  
 *
 * **Parameters**  
 * Required: `U` (maximum fragment size).  
 * Optional: `alpha`, `f`, `coverage`, `cut_side`, `tau`.  
 * Flags: `arc_weights`, `verbose`.  
 * Omitted options use the executable's defaults.  
 *
 * **Outputs**  
 * `graph`: Contracted fragment graph (METIS).  
 * `mapping`: Original vertex-to-fragment mapping.  
 * `kept_edges`: List of retained edges.  
 * `log`: Combined stdout and stderr.  
 *
 * **Configuration**  
 * `params.punch_filter_path`: Path to the PUNCH executable.  
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

    // Optional parameters
    def alpha       = opts.alpha != null ? "--alpha ${opts.alpha}" : ''
    def f           = opts.f != null ? "--f ${opts.f}" : ''
    def coverage    = opts.coverage != null ? "--coverage ${opts.coverage}" : ''
    def cutSide     = opts.cut_side != null ? "--cut-side ${opts.cut_side}" : ''
    def tau         = opts.tau != null ? "--tau ${opts.tau}" : ''

    // Boolean command-line switches
    def arcWeights = opts.arc_weights ? '--arc-weights' : ''
    def verbose = opts.verbose ? '--verbose' : ''

    """
    "${params.tools.punch_filter}" \
        --graph "${graph}" \
        --U ${opts.U} \
        ${alpha} \
        ${f} \
        ${coverage} \
        ${cutSide} \
        ${tau} \
        ${arcWeights} \
        ${verbose} \
        --dump-fragment-graph fragments.graph \
        --dump-partition fragment_mapping.txt \
        --dump-kept-edges kept_edges.txt \
        > punch.log 2>&1
    """
}