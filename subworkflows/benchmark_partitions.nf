include { PARTITION_WITH_REGION_FILTER } from './partition_with_region_filter.nf'
include { SPLIT_EDGES_BY_PARTITION } from '../modules/split_edges_by_partition.nf'
include { IMPORT_SQLPLOT_RESULTS } from '../modules/import_sqlplot_results.nf'

/**
 * Runs the requested partitions and collects their measurements in SQLite.  
 *
 * **Inputs**  
 * `filters`, `partitions`: Filter and partition requests for PARTITION_WITH_REGION_FILTER.  
 * `metadata`: One `(partition_key, fields)` per partition. Fields are added to its RESULT row.  
 * `filterTools`, `partitionTools`: Each supplies one `(resolved_commit, executable)`.  
 * The caller supplies unique partition keys and associates each with its filter key.  
 *
 * **Outputs**  
 * `database`: SQLite file with one row per partition in the runs table.  
 */
workflow BENCHMARK_PARTITIONS {
    take:
    filters
    partitions
    metadata
    filterTools
    partitionTools

    main:
    PARTITION_WITH_REGION_FILTER(
        filters, partitions,
        filterTools.map { _commit, executable -> executable },
        partitionTools.map { _commit, executable -> executable }
    )

    // Several partitions share the edges produced by one graph/filter repetition.
    def naturalEdges = PARTITION_WITH_REGION_FILTER.out.natural_edges
    def totals = naturalEdges.map { filterKey, edges -> tuple(filterKey, FileUtils.countRows(edges)) }
    def edgeInputs = PARTITION_WITH_REGION_FILTER.out.partitions
        .join(partitions.map { key, filterKey, _opts -> tuple(key, filterKey) },
              failOnDuplicate: true, failOnMismatch: true)
        .map { key, partition, filterKey -> tuple(filterKey, key, partition) }
        .combine(naturalEdges, by: 0)
        .map { _filterKey, key, partition, edges -> tuple(key, partition, edges) }
    SPLIT_EDGES_BY_PARTITION(edgeInputs)

    def partitionTotals = partitions.map { key, filterKey, _opts -> tuple(filterKey, key) }
        .combine(totals, by: 0)
        .map { _filterKey, key, total -> tuple(key, total) }
    def counts = SPLIT_EDGES_BY_PARTITION.out.between
        .map { key, edges -> tuple(key, FileUtils.countRows(edges)) }
        .join(partitionTotals, failOnDuplicate: true, failOnMismatch: true)

    def records = PARTITION_WITH_REGION_FILTER.out.results
        .join(metadata, failOnDuplicate: true, failOnMismatch: true)
        .join(counts, failOnDuplicate: true, failOnMismatch: true)
        .combine(filterTools.map { commit, _executable -> commit })
        .combine(partitionTools.map { commit, _executable -> commit })
        .map { _key, result, fields, cut, total, filterCommit, partitionCommit ->
            SqlPlotResult.withFields(result.text, [
                natural_edges_cut: cut,
                total_natural_edges: total
            ] + fields + [
                region_filter_commit: filterCommit,
                mt_kahypar_commit: partitionCommit
            ])
        }.collectFile(name: 'runs.result', newLine: true, sort: true)
    IMPORT_SQLPLOT_RESULTS(records, 'runs')

    emit:
    database = IMPORT_SQLPLOT_RESULTS.out.database
}
