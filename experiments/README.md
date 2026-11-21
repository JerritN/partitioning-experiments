# Linear experiment files

An experiment describes a sequence of stages. Each workflow chooses which sequences it can execute, how to supply inputs, and which results to publish. The RegionFilter integration workflow takes METIS graphs and executes `region_filter` followed by `mt_kahypar`.

Run the [Luxembourg example](luxembourg-rating-policies.yaml) from the repository root with the same machine configuration and SQLite-enabled sqlplot-tools installation as the CLI benchmark:

```bash
nextflow run workflows/experiment_region_filter_integration.nf \
  -params-file experiments/luxembourg-rating-policies.yaml \
  --graph_dir "$HOME/data" \
  -output-dir results/luxembourg-rating-policies
```

This runs one filter trial and twenty partitions. The original CLI benchmark is also available. To migrate a file from the earlier prototype, move each tool's configuration into the ordered `stages` list, add its `tool`, and give it the `id` used in your comparisons.

## Stage definitions

| Field | Meaning |
|---|---|
| `stages` | Nonempty list in execution order. Each trial consumes its immediate parent's result. |
| `id` | Unique stage name within this experiment, used in comparisons. |
| `tool` | Name interpreted by the workflow. A chain can use the same tool at multiple stage IDs. |
| `defaults` | Stage option map, empty by default. |
| `variants` | Named option maps. Each overrides the defaults by top-level option name. Omit for one variant named `default`. A list-valued option is passed as one value. |
| `repetitions` | Positive number of executions per selected variant **per parent trial**. Defaults to one. Each repetition keeps its variant's options, including the seed. |
| `comparisons` | Optional list of selections mapping stage IDs to variant names. Each selection permits all combinations at unspecified stages. The union of the selections runs once. Omit for the full cross product. |

For example, this fragment pairs two filter settings with two partition settings:

```yaml
  stages:
    - id: filter
      tool: region_filter
      variants:
        small: {k: 4}
        large: {k: 8}
    - id: partition
      tool: mt_kahypar
      defaults: {epsilon: 0.03, objective: cut, preset_type: default}
      variants:
        four: {blocks: 4}
        eight: {blocks: 8}
  comparisons:
    - {filter: small, partition: four}
    - {filter: large, partition: eight}
```

The same selection syntax works across nonadjacent stages. If a workflow adds a stage between `filter` and `partition`, each matching combination runs through every selected variant and repetition of that middle stage. Each filter trial executes once regardless of how many downstream trials use it.

## Plan contract for workflow authors

Call `LinearExperiment.plan(stages, comparisons)` once for an input-independent plan. It returns one batch per stage in declaration order. Each batch contains its `id`, `tool`, `repetitions` and `trials`. Each trial contains:

- `key`: the ordered path of `(stage, variant, repetition)` records from the first stage through this one.
- `parentKey`: the immediate predecessor's key, or null for first-stage trials.
- `variant`, `repetition`, `options`: the local variant name, one-based repetition, and merged option map.

A workflow can iterate the batches in order or match outputs by key. When applying a plan to several inputs, pair each trial key and parent key with the same input ID. This preserves sharing and keeps runs on different inputs distinct. Single-stage workflows just consume the first batch. The planner has no dependency on Nextflow channels, graph files, executables, or tool option schemas.

## RegionFilter integration

Within `experiment`, supply a `name` and distinct `graphs` paths resolved against `--graph_dir`. The integration validates the stage sequence, graph files and selected options before building. The parser accepts other chains, such as PunchFilter followed by Mt-KaHyPar, for workflows that implement them.

Use the option names in the [RegionFilter](../modules/region_filter.nf) and [Mt-KaHyPar](../modules/mt_kahypar.nf) processes. RegionFilter requires exactly one of `k` and `U`. Mt-KaHyPar requires `blocks`, `epsilon`, `objective` and `preset_type`. The integration supplies `file_format: metis`, `edge_metadata_type: natural_edge` and the default rating policy `ignore`. Repository paths, pinned tool revisions and build options use the existing Nextflow configuration.

The only published file is `runs.sqlite`. The `runs` table includes experiment and variant names, repetitions, resolved commits, merged options as JSON, natural-edge counts and native partition measurements.

```sql
SELECT graph_id, filter_variant, partition_variant, COUNT(*) AS trials,
       AVG(cut) AS mean_cut, AVG(natural_edges_cut) AS mean_natural_edges_cut
FROM runs
GROUP BY experiment_name, graph_id, filter_variant, partition_variant;
```
