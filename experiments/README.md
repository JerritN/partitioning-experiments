# RegionFilter and Mt-KaHyPar experiments

From the repository root, run the example with a directory containing the decompressed METIS graph. Use the same machine configuration, tool revisions and SQLite-enabled sqlplot-tools installation as for the existing benchmark.

```bash
nextflow run workflows/experiment_region_filter_integration.nf \
  -params-file experiments/luxembourg-rating-policies.yaml \
  --graph_dir "$HOME/data" \
  -output-dir results/luxembourg-rating-policies
```

The example runs RegionFilter once and partitions its output with four rating policies, five times each. It publishes one file, `runs.sqlite`. The original `benchmark_region_filter_integration.nf` remains available for experiments driven by the existing CLI flags.

## Experiment definition

| Field under `experiment` | Meaning |
|---|---|
| `name` | Label recorded in every database row. |
| `graphs` | Explicit list of graph paths, resolved against `--graph_dir`. Each listed path is its graph ID. |
| `region_filter`, `mt_kahypar` | Each stage has a required map of named `variants`, optional `defaults`, and a positive `repetitions` count (default 1). An empty variant inherits all stage defaults. |
| `comparisons` | Optional list of named filter/partition pairs. Omit it to run every partition variant against every filter variant. |

Use the option names documented by the [RegionFilter](../modules/region_filter.nf) and [Mt-KaHyPar](../modules/mt_kahypar.nf) processes. Each variant overrides its stage defaults. RegionFilter requires exactly one of `k` and `U`. Mt-KaHyPar requires `blocks`, `epsilon`, `objective` and `preset_type`. The integration supplies `file_format: metis`, `edge_metadata_type: natural_edge`, and the default rating policy `ignore`. A list such as `region_factors: [0.25, 0.5]` is passed to one invocation. Use separate named variants to compare settings.

A filter run is identified by its graph, filter variant and filter repetition. Every matching partition request reuses that run’s edges. Partition repetitions reuse their variant’s options, including any explicit seed. To vary seeds, declare variants with different `seed` values. Repository paths, build settings and pinned revisions retain their existing Nextflow configuration and CLI overrides.

## Pair specific variants

For example, to compare two matched block counts, keep the example's `name` and `graphs` and use the following stage definitions under `experiment`:

```yaml
  region_filter:
    variants:
      filter4: {k: 4}
      filter8: {k: 8}
  mt_kahypar:
    defaults: {epsilon: 0.03, objective: cut, preset_type: default}
    variants:
      partition4: {blocks: 4}
      partition8: {blocks: 8}
  comparisons:
    - {filter: filter4, partition: partition4}
    - {filter: filter8, partition: partition8}
```

The `runs` table records the experiment and variant names, both repetition indices, resolved tool commits, natural-edge counts, and Mt-KaHyPar's native measurements. The `region_filter_options` and `mt_kahypar_options` JSON columns contain the merged options passed to the wrappers. Settings omitted from those maps follow the wrapper or tool defaults.

```sql
SELECT graph_id, filter_variant, partition_variant, COUNT(*) AS trials,
       AVG(cut) AS mean_cut, AVG(natural_edges_cut) AS mean_natural_edges_cut
FROM runs
GROUP BY experiment_name, graph_id, filter_variant, partition_variant;
```
