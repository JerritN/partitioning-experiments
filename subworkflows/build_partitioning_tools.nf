include { BUILD_CMAKE_FROM_GIT } from './build_cmake_from_git.nf'

/**
 * Builds the executables used by the region-filter partitioning experiments.  
 *
 * **Inputs**  
 * `repository`, `threads`: Local Git repository and parallel build jobs.  
 * `tools`: Map from tool name to its revision and CMake build settings.  
 *
 * **Outputs**  
 * `region_filter`, `mt_kahypar`: One `(resolved_commit, executable)` per tool.  
 */
workflow BUILD_PARTITIONING_TOOLS {
    take:
    repository
    threads
    tools

    main:
    requests = channel.fromList(tools.collect { name, tool ->
        def opts = [preset: tool.cmake_preset, target: tool.target, binary: tool.binary, threads: threads]
        if (tool.definitions != null) opts.definitions = tool.definitions
        tuple(name, repository, tool.revision, opts)
    })
    BUILD_CMAKE_FROM_GIT(requests)
    binaries = BUILD_CMAKE_FROM_GIT.out.binary.branch { name, commit, binary ->
        region_filter: name == 'region_filter'
            return tuple(commit, binary)
        mt_kahypar: name == 'mt_kahypar'
            return tuple(commit, binary)
    }

    emit:
    region_filter = binaries.region_filter
    mt_kahypar = binaries.mt_kahypar
}
