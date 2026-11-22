// Run from the repository root with nextflow run tests/linear_experiment.nf

workflow {
    def planDocument = { document -> experiment.ExperimentPlanner.plan(experiment.ExperimentParser.parse(document)) }
    def documentSpec = [
        name: 'planner-test',
        dimensions: [graph: ['a','b'], size: [s: [k: 2, blocks: 4], l: [k: 4, blocks: 8]],
            policy: [true,false], run: [1,2,3]],
        stages: [[tool: 'input', inputs: [path: '${graph}']],
            [tool: 'custom', inputs: [first: [k: '${size.k}'], second: [blocks: '${size.blocks}']]],
            [tool: 'custom', vary: ['run'], inputs: [nested: ['${size.blocks}', '${policy}']]]]
    ]
    def plan = planDocument.call(documentSpec)
    assert plan.stages*.runs*.size() == [2,4,24]
    assert plan.stages.first().runs.every { it.parentKey == null }
    assert plan.stages.last().runs.every { run ->
        def parent = plan.stages[1].runs.find { it.key == run.parentKey }
        parent && parent.inputs.second.blocks == 2 * parent.inputs.first.k && run.inputs.nested == [2 * parent.inputs.first.k, run.choices.policy]
    }
    def repeatedPlan = planDocument.call(documentSpec)
    assert repeatedPlan.stages*.runs*.key == plan.stages*.runs*.key

    def selectors = [[graph: 'a', policy: false], [graph: 'a', size: 's', policy: false]]
    def selected = planDocument.call(documentSpec + [selections: selectors])
    assert selected.stages*.runs*.size() == [1,2,6]
    assert selected.stages.last().runs*.key.toSet().size() == 6
    def stages = documentSpec.stages.collect { it + [:] }
    stages[1].id = 'filter'
    stages[1].vary = ['run']
    def paired = planDocument.call(documentSpec + [stages: stages])
    paired.verifyStageSequence(['input', 'custom', 'custom'])
    try {
        paired.verifyStageSequence(['custom', 'input', 'custom'])
        assert false : 'Incorrect stage order was accepted'
    } catch (IllegalArgumentException expected) {
        assert expected.message.contains('received [input, custom, custom]')
    }
    assert paired.stages*.runs*.size() == [2,12,24]
    assert paired.stages.last().runs*.key.toSet() == plan.stages.last().runs*.key.toSet()
    assert planDocument.call([name:'fixed', stages:[[tool:'input']]]).stages[0].runs.size() == 1
    def example = experiment.ExperimentFile.read(file('experiments/luxembourg-rating-policies.yaml'))
    def direct = new experiment.ExperimentDefinition(example.name,
        example.dimensions + [run: [1:1, 2:2, 3:3, 4:4, 5:5]], [
            new experiment.StageDefinition('metis_graph', [path: new experiment.DimensionReference('graph', [])]),
            new experiment.StageDefinition('region_filter', [options: [k: new experiment.DimensionReference('size', ['filter_k'])]]),
            new experiment.StageDefinition('mt_kahypar', [options: [blocks: new experiment.DimensionReference('size', ['blocks']),
                c_rating_edge_metadata: new experiment.DimensionReference('policy', []), epsilon: 0.03d,
                objective: 'cut', preset_type: 'default', threads: 4]], ['run'])
        ])
    assert experiment.ExperimentPlanner.plan(direct) == planDocument.call(example)
    def fixed = [name: 'fixed', stages: [[tool: 'input']]]
    def malformed = [
        [fixed + [dimensions: ['bad-name': [1]]], 'Invalid dimension name'],
        [fixed + [dimensions: [size: [[k: 2]]]], 'nonempty list of labels'],
        [fixed + [stages: [[tool: 'input', vary: [2]]]], 'dimension names in vary'],
        [fixed + [selections: [false]], 'selection map']
    ]
    malformed.each { spec, message ->
        try {
            experiment.ExperimentParser.parse(spec)
            assert false : 'Parser accepted malformed input'
        } catch (IllegalArgumentException expected) {
            assert expected.message.contains(message)
        }
    }

    def records = [name: 'records', dimensions: [size: [small: [k: 2], large: [:]]],
        stages: [[tool: 'input', inputs: [k: '${size.k}']]]]
    assert planDocument.call(records + [selections: [[size: 'small']]]).stages[0].runs*.inputs == [[k: 2]]
    def incoherent = [
        [documentSpec + [selections: [[graph: 'missing']]], 'Unknown selection'],
        [fixed + [stages: [[tool: 'input', inputs: [x: '${missing}']]]], 'Unknown dimensions'],
        [fixed + [stages: [[tool: 'a', id: 'same'], [tool: 'b', id: 'same']]], 'Duplicate stage id'],
        [fixed + [dimensions: [unused: [1]]], 'Unused dimensions'],
        [records, 'Missing k for size=large']
    ]
    incoherent.each { spec, message ->
        def definition = experiment.ExperimentParser.parse(spec)
        try {
            experiment.ExperimentPlanner.plan(definition)
            assert false : 'Planner accepted an incoherent experiment'
        } catch (IllegalArgumentException expected) {
            assert expected.message.contains(message)
        }
    }
}
