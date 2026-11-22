// Run from the repository root with nextflow run tests/linear_experiment.nf

workflow {
    def experiment = [
        name: 'planner-test',
        dimensions: [graph: ['a','b'], size: [s: [k: 2, blocks: 4], l: [k: 4, blocks: 8]],
            policy: [true,false], run: [1,2,3]],
        stages: [[tool: 'input', inputs: [path: '${graph}']],
            [tool: 'custom', inputs: [first: [k: '${size.k}'], second: [blocks: '${size.blocks}']]],
            [tool: 'custom', vary: ['run'], inputs: [nested: ['${size.blocks}', '${policy}']]]]
    ]
    def plan = LinearExperiment.plan(experiment)
    assert plan*.runs*.size() == [2,4,24]
    assert plan.first().runs.every { it.parentKey == null }
    assert plan.last().runs.every { run ->
        def parent = plan[1].runs.find { it.key == run.parentKey }
        parent && parent.inputs.second.blocks == 2 * parent.inputs.first.k && run.inputs.nested == [2 * parent.inputs.first.k, run.choices.policy]
    }
    def selectors = [[graph: 'a', policy: false], [graph: 'a', size: 's', policy: false]]
    def selected = LinearExperiment.plan(experiment + [selections: selectors])
    assert selected*.runs*.size() == [1,2,6]
    assert selected.last().runs*.key.toSet().size() == 6
    def stages = experiment.stages.collect { it + [:] }
    stages[1].id = 'filter'
    stages[1].vary = ['run']
    def paired = LinearExperiment.plan(experiment + [stages: stages])
    LinearExperiment.verifyStageSequence(paired, ['input', 'custom', 'custom'])
    try {
        LinearExperiment.verifyStageSequence(paired, ['custom', 'input', 'custom'])
        assert false : 'Incorrect stage order was accepted'
    } catch (IllegalArgumentException expected) {
        assert expected.message.contains('received [input, custom, custom]')
    }
    assert paired*.runs*.size() == [2,12,24]
    assert paired.last().runs*.key.toSet() == plan.last().runs*.key.toSet()
    assert LinearExperiment.plan([name:'fixed', stages:[[tool:'input']]])[0].runs.size() == 1
    def bad = [experiment + [selections: [[graph:'missing']]],
        experiment + [stages: [[tool:'input', inputs:[x:'${missing}']]]],
        [name:'bad', stages:[[tool:'input', inputs:[x:'${size.other}']]],
            dimensions:[size:[s:[k:2]]]]]
    bad.each { spec ->
        try {
            LinearExperiment.plan(spec)
            assert false : 'Invalid experiment was accepted'
        } catch (IllegalArgumentException expected) {
            assert expected.message
        }
    }
}
