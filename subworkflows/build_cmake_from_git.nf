include { GIT_CHECKOUT } from '../modules/git_checkout.nf'
include { CMAKE_BUILD } from '../modules/cmake_build.nf'

/**
 * Builds CMake targets from paired repository revisions and build options.  
 *
 * **Inputs**  
 * `requests`: Channel of `(context, repository, revision, build_opts)` tuples.  
 * The repository is a local Git checkout accessible to the Nextflow launcher.  
 *
 * **Outputs**  
 * `binary`, `build`, `configure_log`, `build_log`: CMake outputs with the request context extended by `commit` and `build_opts`.  
 * Requests with the same repository and resolved commit share one source checkout.  
 */
workflow BUILD_CMAKE_FROM_GIT {
    take:
    requests

    main:
    resolved = requests.map { context, repository, revision, opts ->
        def commit = GitUtils.resolveCommit(repository, revision)
        tuple(repository, commit, context, opts)
    }
    checkouts = resolved.map { repository, commit, context, opts ->
        tuple(repository, commit)
    }.unique().map { repository, commit ->
        tuple([repository: repository, commit: commit], repository, commit)
    }

    GIT_CHECKOUT(checkouts)
    sources = GIT_CHECKOUT.out.source.map { key, source ->
        tuple(key.repository, key.commit, source)
    }
    build_inputs = resolved.combine(sources, by: [0, 1]).map { repository, commit, context, opts, source ->
        tuple(context + [commit: commit, build_opts: opts], source, opts)
    }
    CMAKE_BUILD(build_inputs)

    emit:
    binary = CMAKE_BUILD.out.binary
    build = CMAKE_BUILD.out.build
    configure_log = CMAKE_BUILD.out.configure_log
    build_log = CMAKE_BUILD.out.build_log
}
