
include { GIT_CHECKOUT } from '../modules/git_checkout.nf'
include { CMAKE_BUILD } from '../modules/cmake_build.nf'
include { PUNCH_FILTER } from '../modules/punch_filter.nf'
include { BUILD_CMAKE_PROJECT } from '../subworkflows/build_cmake_project.nf'

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

    // 2. Configure and compile PunchFilter.
    def commit = GitUtils.resolveCommit(
        repository,
        params.commit
    )

    def source = tuple(
        [commit: commit],
        repository,
        commit
    )

    def buildOpts = [
        preset: params.cmake_preset,
        target: 'PunchFilter',
        binary: params.mt_kahypar.punch_filter_binary,
        threads: 8
    ]

    BUILD_CMAKE_PROJECT(
        source,
        channel.value(buildOpts)
    )

    // 3. Run PUNCH with the compiled executable.
    def graphFile = file(params.graph, checkIfExists: true)
    def punchOpts = [U: params.U]

    def punchInputs = BUILD_CMAKE_PROJECT.out.binaries.map {
        context, binaries ->
            tuple(
                context,
                CollectionUtils.findFile(binaries, 'PunchFilter'),
                graphFile,
                punchOpts
            )
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
