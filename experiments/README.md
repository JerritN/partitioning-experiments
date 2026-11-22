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
def document = experiment.ExperimentFile.read(path)
def definition = experiment.ExperimentParser.parse(document)
def plan = experiment.ExperimentPlanner.plan(definition)
plan.verifyStageSequence(['metis_graph', 'region_filter', 'mt_kahypar'])
```

`ExperimentFile` decodes YAML. `ExperimentParser` translates shorthand choices and reference strings into an `ExperimentDefinition` containing ordered `StageDefinition` objects. References in their input templates are `DimensionReference` values. Code can also construct these definitions directly using normalized choice maps. Definitions hold data, including each stage’s explicit `vary` list. The parser checks document shape, identifier syntax and choice label types. The planner checks selection labels before expansion, verifies explicit IDs and dimension use as it visits each stage, and reports unused dimensions after the last stage. Record fields are resolved only for selected choices.

`ExperimentPlanner` expands that definition into an `Experiment` with a name and ordered `stages`. Each `PlannedStage` contains `PlannedRun` objects. Planning works entirely in memory. The workflow validates the supported stage sequence and adapts each run’s inputs to process requests.

Each planned stage has `tool`, `id` (defaults to the tool name), and `runs`. Each run contains resolved `inputs`, inherited and newly bound choice labels in `choices`, an opaque `key`, and the immediate predecessor's `parentKey` (null for the first stage). Compare opaque `RunKey` values when linking runs in memory. Use `key.toTaskKey()` when constructing Nextflow tuples so cached tasks can restore their keys on resume. Each upstream run appears once even when several children share it. The executing workflow connects named inputs and resolves graph paths before launching tools.
