// Run from the repository root with nextflow run tests/linear_experiment.nf

workflow {
    def planDocument = { document -> ExperimentPlanner.plan(ExperimentParser.parse(document)) }
    def experiment = [
        name: 'planner-test',
        dimensions: [graph: ['a','b'], size: [s: [k: 2, blocks: 4], l: [k: 4, blocks: 8]],
            policy: [true,false], run: [1,2,3]],
        stages: [[tool: 'input', inputs: [path: '${graph}']],
            [tool: 'custom', inputs: [first: [k: '${size.k}'], second: [blocks: '${size.blocks}']]],
            [tool: 'custom', vary: ['run'], inputs: [nested: ['${size.blocks}', '${policy}']]]]
    ]
    def plan = planDocument.call(experiment)
    assert plan.stages*.runs*.size() == [2,4,24]
    assert plan.stages.first().runs.every { it.parentKey == null }
    assert plan.stages.last().runs.every { run ->
        def parent = plan.stages[1].runs.find { it.key == run.parentKey }
        parent && parent.inputs.second.blocks == 2 * parent.inputs.first.k && run.inputs.nested == [2 * parent.inputs.first.k, run.choices.policy]
    }
    def selectors = [[graph: 'a', policy: false], [graph: 'a', size: 's', policy: false]]
    def selected = planDocument.call(experiment + [selections: selectors])
    assert selected.stages*.runs*.size() == [1,2,6]
    assert selected.stages.last().runs*.key.toSet().size() == 6
    def stages = experiment.stages.collect { it + [:] }
    stages[1].id = 'filter'
    stages[1].vary = ['run']
    def paired = planDocument.call(experiment + [stages: stages])
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
    def example = ExperimentFile.read(file('experiments/luxembourg-rating-policies.yaml'))
    def direct = new ExperimentDefinition(example.name,
        example.dimensions + [run: [1:1, 2:2, 3:3, 4:4, 5:5]], [
            new StageDefinition('metis_graph', [path: new DimensionReference('graph', [])]),
            new StageDefinition('region_filter', [options: [k: new DimensionReference('size', ['filter_k'])]]),
            new StageDefinition('mt_kahypar', [options: [blocks: new DimensionReference('size', ['blocks']),
                c_rating_edge_metadata: new DimensionReference('policy', []), epsilon: 0.03d,
                objective: 'cut', preset_type: 'default', threads: 4]], ['run'])
        ])
    assert ExperimentPlanner.plan(direct) == planDocument.call(example)
    def bad = [experiment + [selections: [[graph:'missing']]],
        experiment + [stages: [[tool:'input', inputs:[x:'${missing}']]]],
        [name:'bad', stages:[[tool:'input', inputs:[x:'${size.other}']]],
            dimensions:[size:[s:[k:2]]]]]
    bad.each { spec ->
        try {
            planDocument.call(spec)
            assert false : 'Invalid experiment was accepted'
        } catch (IllegalArgumentException expected) {
            assert expected.message
        }
    }
}
