// Run from the repository root with nextflow run tests/linear_experiment.nf
workflow {
    def experiment = [
        name: 'planner-test',
        dimensions: [graph: ['a','b'], size: [s: [k: 2, blocks: 4], l: [k: 4, blocks: 8]],
            policy: [true,false], run: [1,2,3]],
        stages: [[tool: 'input', options: [path: '${graph}']],
            [tool: 'custom', options: [k: '${size.k}']],
            [tool: 'custom', vary: ['run'], options: [nested: ['${size.blocks}', '${policy}']]]]
    ]
    def plan = LinearExperiment.plan(experiment)
    assert plan*.requests*.size() == [2,4,24]
    assert plan.first().requests.every { it.parentKey == null }
    assert plan.last().requests.every { trial ->
        def parent = plan[1].requests.find { it.key == trial.parentKey }
        parent && trial.options.nested == [2 * parent.options.k, trial.choices.policy]
    }
    def selectors = [[graph: 'a', policy: false], [graph: 'a', size: 's', policy: false]]
    def selected = LinearExperiment.plan(experiment + [selections: selectors])
    assert selected*.requests*.size() == [1,2,6]
    assert selected.last().requests*.key.toSet().size() == 6
    def stages = experiment.stages.collect { it + [:] }
    stages[1].id = 'filter'
    stages[1].vary = ['run']
    def paired = LinearExperiment.plan(experiment + [stages: stages])
    assert paired*.requests*.size() == [2,12,24]
    assert paired.last().requests*.key.toSet() == plan.last().requests*.key.toSet()
    assert LinearExperiment.plan([name:'fixed', stages:[[tool:'input']]])[0].requests.size() == 1
    def bad = [experiment + [selections: [[graph:'missing']]],
        experiment + [stages: [[tool:'input', options:[x:'${missing}']]]],
        [name:'bad', stages:[[tool:'input', options:[x:'${size.other}']]],
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
