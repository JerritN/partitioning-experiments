
include { GIT_CHECKOUT } from '../modules/git_checkout.nf'
include { CMAKE_BUILD } from '../modules/cmake_build.nf'
include { PUNCH_FILTER } from '../modules/punch_filter.nf'

params {
    graph: String = "${params.project_path}/data/belgium.osm.graph"

    // Optional; if omitted, use HEAD
    commit: String?

    cmake_preset: String = 'minimal'
    U: Integer = 1000
}

workflow {
    main:
    def repository = "${params.project_path}/mt-kahypar"

    // Resolve HEAD before creating the Nextflow task.
    def commit = params.commit

    if (commit == null) {
        def git = [
            'git', '-C', repository.toString(), 'rev-parse', 'HEAD'
        ].execute()

        def stdout = new StringBuffer()
        def stderr = new StringBuffer()
        git.consumeProcessOutput(stdout, stderr)

        assert git.waitFor() == 0 :
            "Could not resolve HEAD: ${stderr}"

        commit = stdout.toString().trim()
    }

    assert commit ==~ /(?i)[0-9a-f]{40,64}/ :
        "Expected a full Git commit hash"

    // 1. Obtain the selected source revision.
    GIT_CHECKOUT(
        tuple(
            [commit: commit],
            repository,
            commit
        )
    )

    // 2. Configure and compile PunchFilter.
    def buildOpts = [
        preset: params.cmake_preset,
        target: 'PunchFilter',
        binary: params.mt_kahypar.punch_filter_binary,
        threads: 8,
        cache_mode: true
    ]

    def buildInputs = GIT_CHECKOUT.out.source.map {
        context, source ->
            tuple(context, source, buildOpts)
    }

    CMAKE_BUILD(buildInputs)

    // 3. Run PUNCH with the compiled executable.
    def graph = file(params.graph, checkIfExists: true)

    def punchOpts = [
        U: params.U
    ]

    def punchInputs = CMAKE_BUILD.out.binary.map {
        context, binaries ->

            def executable = CollectionUtils
                .asList(binaries)
                .find { file -> file.name == 'PunchFilter' }

            assert executable != null :
                "PunchFilter executable not found"

            tuple(context, executable, graph, punchOpts)
    }

    PUNCH_FILTER(punchInputs)

    // 4. Publish results.
    publish:
    fragments = PUNCH_FILTER.out.graph
    mapping = PUNCH_FILTER.out.mapping
    edges = PUNCH_FILTER.out.kept_edges
    logs = PUNCH_FILTER.out.log
}

output {
    fragments {
        path 'punch/fragments'
    }

    mapping {
        path 'punch/mapping'
    }

    edges {
        path 'punch/edges'
    }

    logs {
        path 'punch/logs'
    }
}
