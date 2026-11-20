include { REGION_FILTER } from '../modules/region_filter.nf'
include { TAKE_COLUMNS } from '../modules/take_columns.nf'
include { MT_KAHYPAR } from '../modules/mt_kahypar.nf'

/**
 * Partitions graphs using the natural edges from the requested filter runs.  
 *
 * **Inputs**  
 * `filter_requests`: Channel of `(filter_key, graph_file, filter_opts)`, one request per unique filter key.  
 * `partition_requests`: Channel of `(partition_key, filter_key, partition_opts)`, one request per partition.  
 * Each partition references an existing filter key. Several partitions may share its edges.  
 * `region_filter`, `mt_kahypar`: Each supplies one executable.  
 *
 * **Outputs**  
 * `natural_edges`, `filter_logs`: One `(filter_key, file)` per filter request.  
 * `partitions`, `partition_logs`, `results`: One `(partition_key, file)` per partition request.  
 * Both keys belong to the caller and pass through unchanged.  
 */
workflow PARTITION_WITH_REGION_FILTER {
    take:
    filter_requests
    partition_requests
    region_filter
    mt_kahypar

    main:
    filters = filter_requests.groupTuple().map { key, graphs, opts ->
        assert graphs.size() == 1 : "Duplicate filter key: ${key}"
        tuple(key, graphs[0], opts[0])
    }
    filterInputs = filters.combine(region_filter).map { key, graph, opts, executable ->
        tuple(key, executable, graph, opts)
    }
    REGION_FILTER(filterInputs)
    TAKE_COLUMNS(REGION_FILTER.out.cut_edges, [1, 2])

    // Match the original graph and its edge file once, then fan out to its partitions.
    filteredGraphs = filters.map { key, graph, _opts -> tuple(key, graph) }
        .join(TAKE_COLUMNS.out.output, failOnDuplicate: true, failOnMismatch: true)
        .map { key, graph, edges -> tuple(key, [graph: graph, edges: edges]) }
    byFilter = partition_requests.map { partitionKey, filterKey, opts ->
        tuple(filterKey, [key: partitionKey, opts: opts])
    }.groupTuple()
    partitionInputs = byFilter.join(filteredGraphs, remainder: true, failOnDuplicate: true)
        .flatMap { filterKey, requests, files ->
            if (requests == null) return []
            assert files != null : "Unknown filter key: ${filterKey}"
            requests.collect { run -> tuple(run.key, files.graph, files.edges, run.opts) }
        }
        .combine(mt_kahypar)
        .map { key, graph, edges, opts, executable -> tuple(key, executable, graph, [], edges, opts) }
    MT_KAHYPAR(partitionInputs)

    emit:
    natural_edges = TAKE_COLUMNS.out.output
    filter_logs = REGION_FILTER.out.log
    partitions = MT_KAHYPAR.out.partition
    partition_logs = MT_KAHYPAR.out.log
    results = MT_KAHYPAR.out.result
}
