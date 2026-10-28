include { GIT_CHECKOUT } from '../modules/git_checkout.nf'
include { CMAKE_BUILD } from '../modules/cmake_build.nf'

/**
 * Builds a CMake project from one or more Git revisions.  
 *
 * **Inputs**  
 * `source_inputs`: Channel of `(context, repository, commit)` tuples.  
 * `build_options`: Channel of option maps.  
 *
 * **Behavior**  
 * Checks out each source revision using `GIT_CHECKOUT`.  
 * Combines every source revision with every build configuration.  
 * Builds each combination independently using `CMAKE_BUILD`.  
 * Multiple configurations can reuse the same source checkout.  
 *
 * **Outputs**  
 * `binaries`: Compiled executables requested in `opts.binary`.  
 * `build`: Complete CMake build directories.  
 * Both outputs retain the source `context`, extended with `build_opts`.  
 *
 * **Requirements**  
 * Git, CMake, and a compatible compiler must be available.  
 */
workflow BUILD_CMAKE_PROJECT {
    take:
    source_inputs
    build_options

    main:
    GIT_CHECKOUT(source_inputs)

    build_inputs = GIT_CHECKOUT.out.source
        .combine(build_options)
        .map { context, source, opts ->
            tuple(context + [build_opts: opts], source, opts)
        }

    CMAKE_BUILD(build_inputs)

    emit:
    binaries = CMAKE_BUILD.out.binary
    build = CMAKE_BUILD.out.build
}
