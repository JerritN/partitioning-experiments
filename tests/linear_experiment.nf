// Run from the repository root: nextflow run tests/linear_experiment.nf
workflow {
    def first = [id: 'a', tool: 'custom', defaults: [weights: [1, 2], limit: 1],
        variants: [x: [:], y: [limit: 3]], repetitions: 2]
    def single = LinearExperiment.plan([first])[0].trials
    assert single.size() == 4 && single.every { it.parentKey == null }
    assert single.last().options == [weights: [1, 2], limit: 3]

    def middle = [id: 'b', tool: 'custom', repetitions: 2]
    def last = [id: 'c', tool: 'measure', variants: [low: [:], high: [:]]]
    def stages = [first, middle, last]
    def grid = LinearExperiment.plan(stages)
    assert grid*.trials*.size() == [4, 8, 16]

    // The narrow selection overlaps the first, and the middle stage is unrestricted.
    def plan = LinearExperiment.plan(stages, [[a: 'x', c: 'low'], [a: 'x', b: 'default', c: 'low'], [a: 'y', c: 'high']])
    assert plan*.trials*.size() == [4, 8, 8]
    assert plan[2].trials.every { run ->
        run.variant == (run.key.first().variant == 'x' ? 'low' : 'high')
    }
    (1..<plan.size()).each { i ->
        def parents = plan[i-1].trials*.key.toSet()
        assert plan[i].trials.every { parents.contains(it.parentKey) }
        assert plan[i].trials*.key.toSet().size() == plan[i].trials.size()
    }
}
