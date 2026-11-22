// Run from the repository root with nextflow run tests/linear_experiment.nf

workflow {
    def makePlan = { spec ->
        def dimensions = LinearExperiment.dimensions(spec.getOrDefault('dimensions', [:]))
        def stages = LinearExperiment.stages(spec.stages, dimensions)
        def selections = spec.getOrDefault('selections', [[:]])
        LinearExperiment.checkSelections(selections, dimensions)
        return LinearExperiment.plan(dimensions, stages, selections)
    }
    def experiment = [
        name: 'planner-test',
        dimensions: [graph: ['a','b'], size: [s: [k: 2, blocks: 4], l: [k: 4, blocks: 8]],
            policy: [true,false], run: [1,2,3]],
        stages: [[tool: 'input', inputs: [path: '${graph}']],
            [tool: 'custom', inputs: [first: [k: '${size.k}'], second: [blocks: '${size.blocks}']]],
            [tool: 'custom', vary: ['run'], inputs: [nested: ['${size.blocks}', '${policy}']]]]
    ]
    def plan = makePlan.call(experiment)
    assert plan*.requests*.size() == [2,4,24]
    assert plan.first().requests.every { it.parentKey == null }
    assert plan.last().requests.every { trial ->
        def parent = plan[1].requests.find { it.key == trial.parentKey }
        parent && parent.inputs.second.blocks == 2 * parent.inputs.first.k && trial.inputs.nested == [2 * parent.inputs.first.k, trial.choices.policy]
    }
    def selectors = [[graph: 'a', policy: false], [graph: 'a', size: 's', policy: false]]
    def selected = makePlan.call(experiment + [selections: selectors])
    assert selected*.requests*.size() == [1,2,6]
    assert selected.last().requests*.key.toSet().size() == 6
    def stages = experiment.stages.collect { it + [:] }
    stages[1].id = 'filter'
    stages[1].vary = ['run']
    def paired = makePlan.call(experiment + [stages: stages])
    assert paired*.requests*.size() == [2,12,24]
    assert paired.last().requests*.key.toSet() == plan.last().requests*.key.toSet()
    assert makePlan.call([name:'fixed', stages:[[tool:'input']]])[0].requests.size() == 1
    def bad = [experiment + [selections: [[graph:'missing']]],
        experiment + [stages: [[tool:'input', inputs:[x:'${missing}']]]],
        [name:'bad', stages:[[tool:'input', inputs:[x:'${size.other}']]],
            dimensions:[size:[s:[k:2]]]]]
    bad.each { spec ->
        try {
            makePlan.call(spec)
            assert false : 'Invalid experiment was accepted'
        } catch (IllegalArgumentException expected) {
            assert expected.message
        }
    }
}
