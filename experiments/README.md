# Linear experiment files

Pass a standalone YAML document with `--experiment`. Machine settings such as graph directories, compiler settings and tool revisions still come from Nextflow configuration or command-line flags. From the repository root, with the same machine configuration and SQLite-enabled sqlplot-tools as the CLI benchmark, run the [Luxembourg example](luxembourg-rating-policies.yaml):

```bash
nextflow run workflows/experiment_region_filter_integration.nf \
  --experiment experiments/luxembourg-rating-policies.yaml \
  --graph_dir "$HOME/data" \
  -output-dir results/luxembourg-rating-policies
```

The example runs one RegionFilter trial and shares its output across four rating policies with five Mt-KaHyPar runs each.

## Defining experiments

Give the experiment a `name` and list its `stages` in execution order. Each stage has a `tool`, an optional descriptive `id`, and an optional `options` map. Stage positions identify calls, so a chain can use a tool more than once. IDs supplied explicitly must be unique.

Declare alternatives under `dimensions`. A list of scalar values uses each value as its own label. A map gives each choice an explicit label and value. Use a record as the value to couple different settings across tools:

```yaml
dimensions:
  size:
    small: {filter_k: 4, blocks: 8}
    large: {filter_k: 8, blocks: 16}
  policy: [ignore, skip_natural_edge]
  run: [1, 2, 3]
```

Reference a dimension in a stage option with `${policy}` or a record field with `${size.filter_k}`. Put the reference in quotes when writing inline YAML maps. The reference occupies the whole value and preserves its type, including inside lists or nested maps. Supply literal options directly. For the example above, bind the filter's `k` to `${size.filter_k}` and the partitioner's `blocks` to `${size.blocks}` to keep the two settings paired.

A dimension expands the first time a stage references it or lists it under `vary`. Later stages inherit that choice. Independent dimensions form a cross product. For three partition runs per filter output, add `vary: [run]` to the partition stage. For three independently repeated filter outputs, move it to the filter stage. For three partition runs under *each* repeated filter, declare two repetition dimensions and introduce one at each stage. Repetitions leave tool options, including seeds, as specified.

Optional `selections` restrict which combinations run. Each entry matches choice labels, omitted dimensions are unrestricted, and overlapping entries contribute a run only once. For the dimensions above:

```yaml
selections:
  - {size: small}
  - {policy: ignore}
```

This runs both policies for the small size and only `ignore` for the large size. With a single graph and three partition repetitions, it creates two filter calls and nine partition calls.

## Plan contract

The workflow loads YAML with `ExperimentFile.read(path)`. Its `planExperiment` function checks the document fields, experiment name and required tool sequence. It calls the reusable helpers `LinearExperiment.dimensions`, `stages` and `checkSelections` for the shared dimension syntax, then calls `LinearExperiment.plan(dimensions, stages, selections)` to expand the chain. Each workflow defines its own tool options and validation rules. The planner performs no file access and accepts arbitrary chain lengths.

Each batch has `tool`, `id` (defaults to the tool name), and `requests`. Each request contains resolved `options`, inherited and newly bound choice labels in `choices`, an opaque `key`, and the immediate predecessor's `parentKey` (null for the first stage). Join requests to outputs by those keys. Each upstream request appears once even when several children share it. The executing workflow validates selected options and resolves input files before launching tools.

## RegionFilter integration

This workflow expects `metis_graph`, `region_filter`, and `mt_kahypar`, in that order. The graph stage takes a `path` resolved against `--graph_dir`. See the [RegionFilter](../modules/region_filter.nf) and [Mt-KaHyPar](../modules/mt_kahypar.nf) processes for option names. RegionFilter requires exactly one of `k` and `U`. Mt-KaHyPar requires `blocks`, `epsilon`, `objective` and `preset_type`. The workflow supplies METIS format, natural-edge metadata and the default rating policy `ignore`.

The workflow publishes `runs.sqlite`. Its `runs` table includes graph path, selected dimension labels, resolved tool options, tool revisions, native partition measurements and natural-edge counts. For the supplied example:

```sql
SELECT graph_id, json_extract(dimension_choices, '$.size') AS size_label,
       rating_policy, COUNT(*) AS runs, AVG(cut) AS mean_cut,
       AVG(natural_edges_cut) AS mean_natural_edges_cut
FROM runs
GROUP BY experiment_name, graph_id, size_label, rating_policy;
```

To migrate an earlier experiment, remove the outer `experiment` wrapper, move graph paths into the first stage, put constant defaults in `options`, and turn variants and repetition counts into dimensions. Replace stage-based comparisons with selections on dimension labels.
