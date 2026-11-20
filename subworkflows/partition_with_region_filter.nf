include { REGION_FILTER } from '../modules/region_filter.nf'
include { TAKE_COLUMNS } from '../modules/take_columns.nf'
include { MT_KAHYPAR } from '../modules/mt_kahypar.nf'

/**
 * Filters each distinct graph/filter request and partitions with its natural edges.  
 *
 * **Inputs**  
 * `runs`: Channel of `(context, graph, filter_opts, partition_opts)`, one tuple per partition.  
 * Supply `context.graph` as the graph ID. Optional `context.filterRepetition` selects an independent filter run (default: 1).  
 * Keep partition repetitions distinct in `context`. Tool options are passed to their respective processes.  
 * `region_filter`, `mt_kahypar`: Each supplies one `(revision, executable)` tuple.  
 *
 * **Outputs**  
 * `natural_edges`, `filter_logs`: File paired with the filter key (graph ID/file, executable, revision, options, and filter repetition).  
 * `partitions`, `partition_logs`, `results`: File paired with the run context extended by `filterKey`, `kahyparOpts`, and `kahyparCommit`.  
 */
workflow PARTITION_WITH_REGION_FILTER {
    take:
    runs
    region_filter
    mt_kahypar

    main:
    requests = runs.combine(region_filter).map { context, graph, filterOpts, partitionOpts, commit, executable ->
        def key = [graph: context.graph, graphFile: graph, executable: executable, commit: commit,
                   opts: filterOpts, repetition: context.get('filterRepetition', 1)]
        tuple(key, context, partitionOpts)
    }
    filterInputs = requests.map { key, _context, _opts -> key }
        .unique()
        .map { key -> tuple(key, key.executable, key.graphFile, key.opts) }

    REGION_FILTER(filterInputs)
    TAKE_COLUMNS(REGION_FILTER.out.cut_edges, [1, 2])

    partitionInputs = requests.combine(TAKE_COLUMNS.out.output, by: 0)
        .combine(mt_kahypar)
        .map { key, context, opts, edges, commit, executable ->
            def run = context + [filterKey: key, kahyparOpts: opts, kahyparCommit: commit]
            tuple(run, executable, key.graphFile, [], edges, opts)
        }
    MT_KAHYPAR(partitionInputs)

    emit:
    natural_edges = TAKE_COLUMNS.out.output
    filter_logs = REGION_FILTER.out.log
    partitions = MT_KAHYPAR.out.partition
    partition_logs = MT_KAHYPAR.out.log
    results = MT_KAHYPAR.out.result
}
