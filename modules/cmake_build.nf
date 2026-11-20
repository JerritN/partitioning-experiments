
/**
 * Configures and builds a CMake project.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `source`: Directory containing the CMake project.  
 * `opts`: Map of CMake configuration and build options.  
 *
 * **Optional parameters (`opts`)**  
 * `preset`: CMake configure preset.  
 * `definitions`: Map of additional CMake cache variables (`-D`).  
 * `target`: Build target or list of targets (default: all).  
 * `binary`: Executable path or list of paths relative to `build/`, copied to `bin/`.  
 *
 * **Execution options (`opts`)**  
 * `threads`: Number of parallel build jobs (default: 1).  
 *
 * **Outputs**  
 * `build`: Complete CMake build directory.  
 * `binary`: Selected executable, if requested.  
 * `configure_log`: CMake configuration output.  
 * `build_log`: CMake compilation output.  
 * All outputs retain the original `key`.  
 *
 * **Requirements**  
 * CMake, the selected generator, and a compatible compiler must be available.  
 */
process CMAKE_BUILD {
    label 'compilation'
    cache params.get('cache_cmake_build', true)

    cpus { opts.threads ?: 1 }

    input:
    tuple val(key), path(source), val(opts)

    output:
    tuple val(key), path('build'),
        emit: build

    tuple val(key), path('bin/*', arity: '1..*'),
        optional: true,
        emit: binary

    tuple val(key), path('configure.log'),
        emit: configure_log

    tuple val(key), path('build.log'),
        emit: build_log

    script:
    def configure = new CommandBuilder('cmake')
        .add('-S', source)
        .add('-B', 'build')
        .addIf(opts.preset != null, '--preset', opts.preset)

    (opts.definitions ?: [:]).each { name, value ->
        assert value != null :
            "CMake definition ${name} must not be null"

        def cmakeValue = value instanceof Boolean
            ? (value ? 'ON' : 'OFF')
            : value

        configure.add("-D${name}=${cmakeValue}")
    }

    def build = new CommandBuilder('cmake')
        .add('--build', 'build')
        .add('--parallel', "${task.cpus}")

    def targets = CollectionUtils.asList(opts.target)
    if (targets) {
        build.add('--target').addAll(targets)
    }

    def script = new ScriptBuilder()
        .addCommand(configure, "configure.log", true)
        .addCommand(build, "build.log", true)

    def binaries = CollectionUtils.asList(opts.binary)
    if (binaries) {
        script.addCommand(new CommandBuilder('mkdir').add('-p', 'bin'))

        binaries.each { value  ->
            def binary = value.toString()

            assert binary &&
                !binary.startsWith('/') &&
                !binary.tokenize('/').contains('..') :
                "Invalid binary path: ${binary}"

            script.addCommand(new CommandBuilder('cp').add("build/${binary}", 'bin/'))
        }
    }

    return script.build()
}