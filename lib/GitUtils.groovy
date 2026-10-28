
class GitUtils {

    /**
     * Resolves a Git revision to its full commit hash.
     *
     * Defaults to HEAD if no revision is provided.
     */
    static String resolveCommit(
        String repository,
        String revision = null
    ) {
        def command = [
            'git',
            '-C', repository,
            'rev-parse',
            '--verify',
            "${revision ?: 'HEAD'}^{commit}"
        ]

        def process = command.execute()

        def stdout = new StringBuffer()
        def stderr = new StringBuffer()

        process.consumeProcessOutput(stdout, stderr)
        def exitCode = process.waitFor()

        if (exitCode != 0) {
            throw new IllegalArgumentException(
                "Could not resolve Git revision in ${repository}: ${stderr}"
            )
        }

        return stdout.toString().trim()
    }
}
