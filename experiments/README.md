# Linear experiment files

Pass a standalone YAML document with `--experiment`. Machine settings such as graph directories, compiler settings and tool revisions still come from Nextflow configuration or command-line flags. From the repository root, with the same machine configuration and SQLite-enabled sqlplot-tools as the CLI benchmark, run the [Luxembourg example](luxembourg-rating-policies.yaml):

```bash
nextflow run workflows/experiment_region_filter_integration.nf \
  --experiment experiments/luxembourg-rating-policies.yaml \
  --graph_dir "$HOME/data" \
  -output-dir results/luxembourg-rating-policies
```

The example runs one RegionFilter run and shares its output across four rating policies with five Mt-KaHyPar runs each.

## Defining experiments

Give the experiment a `name` and list its `stages` in execution order. Each stage has a `tool`, an optional descriptive `id`, and an optional `inputs` map. Stage positions identify calls, so a chain can use a tool more than once. IDs supplied explicitly must be unique.

Declare alternatives under `dimensions`. A list of scalar values uses each value as its own label. A map gives each choice an explicit label and value. Use a record as the value to couple different settings across tools:

```yaml
dimensions:
  size:
    small: {filter_k: 4, blocks: 8}
    large: {filter_k: 8, blocks: 16}
  policy: [ignore, skip_natural_edge]
  run: [1, 2, 3]
```

Reference a dimension in a stage input with `${policy}` or a record field with `${size.filter_k}`. Put the reference in quotes when writing inline YAML maps. The reference occupies the whole value and preserves its type, including inside lists or nested maps. Supply literal options directly. For the example above, bind the filter's `k` to `${size.filter_k}` and the partitioner's `blocks` to `${size.blocks}` to keep the two settings paired.

A dimension expands the first time a stage references it or lists it under `vary`. Later stages inherit that choice. Independent dimensions form a cross product. For three partition runs per filter output, add `vary: [run]` to the partition stage. For three independently repeated filter outputs, move it to the filter stage. For three partition runs under *each* repeated filter, declare two repetition dimensions and introduce one at each stage. Repetitions leave tool options, including seeds, as specified.

Optional `selections` restrict which combinations run. Each entry matches choice labels, omitted dimensions are unrestricted, and overlapping entries contribute a run only once. For the dimensions above:

```yaml
selections:
  - {size: small}
  - {policy: ignore}
```

This runs both policies for the small size and only `ignore` for the large size. With a single graph and three partition repetitions, it creates two filter calls and nine partition calls.

## Plan contract

The workflow reads the experiment in three steps:

```groovy
def document = ExperimentFile.read(path)
def definition = ExperimentParser.parse(document)
def experiment = ExperimentPlanner.plan(definition)
experiment.verifyStageSequence(['metis_graph', 'region_filter', 'mt_kahypar'])
```

`ExperimentFile` decodes YAML. `ExperimentParser` translates shorthand choices and reference strings into an `ExperimentDefinition` containing ordered `StageDefinition` objects. References in their input templates are `DimensionReference` values. Code can also construct these definitions directly using normalized choice maps. The definition constructor checks shared constraints, including explicit stage IDs, dimension use and selection labels.

`ExperimentPlanner` expands that definition into an `Experiment` with a name and ordered `stages`. Each `PlannedStage` contains `PlannedRun` objects. Planning works entirely in memory. The workflow validates the supported stage sequence and adapts each run’s inputs to process requests.

Each planned stage has `tool`, `id` (defaults to the tool name), and `runs`. Each run contains resolved `inputs`, inherited and newly bound choice labels in `choices`, an opaque `key`, and the immediate predecessor's `parentKey` (null for the first stage). Join runs to outputs by those keys. Each upstream run appears once even when several children share it. The executing workflow connects named inputs and resolves graph paths before launching tools.

## RegionFilter integration

This workflow expects `metis_graph`, `region_filter`, and `mt_kahypar`, in that order. The graph stage takes `inputs.path` resolved against `--graph_dir`. See the [RegionFilter](../modules/region_filter.nf) and [Mt-KaHyPar](../modules/mt_kahypar.nf) processes for option names. RegionFilter requires exactly one of `k` and `U`. Mt-KaHyPar requires `blocks`, `epsilon`, `objective` and `preset_type`. The workflow supplies METIS format, natural-edge metadata and the default rating policy `ignore`.

Both tool stages take an `inputs.options` map. Put `threads` in Mt-KaHyPar's options: the process requests that many CPUs and passes the allocated count to the executable. Ordinary scalar keys use snake_case (`num_vcycles: 2` becomes `--num-vcycles 2`). Boolean true emits a switch; false or null omits it. The modules retain their special handling for explicit boolean-valued options, RegionFilter factors and pair outputs. Tool revisions validate their own algorithm flags at execution. Input and output paths managed by a process are reserved.

The workflow publishes `runs.sqlite`. Its `runs` table includes graph path, selected dimension labels, resolved tool options, tool revisions, native partition measurements and natural-edge counts. For the supplied example:

```sql
SELECT graph_id, json_extract(dimension_choices, '$.size') AS size_label,
       rating_policy, COUNT(*) AS runs, AVG(cut) AS mean_cut,
       AVG(natural_edges_cut) AS mean_natural_edges_cut
FROM runs
GROUP BY experiment_name, graph_id, size_label, rating_policy;
```

To migrate an earlier experiment, remove the outer `experiment` wrapper, move graph paths into the first stage, put constant tool defaults in `inputs.options`, and turn variants and repetition counts into dimensions. Replace stage-based comparisons with selections on dimension labels.

For files using the previous flat stage `options` map, move graph `options.path` to `inputs.path` and each tool’s `options` map to `inputs.options`.
