
/**
 * Checks out a specific Git commit into a task-local directory.  
 *
 * **Inputs**  
 * `context`: Execution context, passed through unchanged.  
 * `repository`: Local Git repository path or remote URL.  
 * `commit`: Full Git commit hash to check out.  
 *
 * **Outputs**  
 * `source`: Git checkout at the requested commit.  
 *
 * **Caching**  
 * Uses repository and commit as value inputs.  
 * Changes to the original working tree do not invalidate the cache.  
 */
process GIT_CHECKOUT {
    label 'source_preparation'

    input:
    tuple val(context), val(repository), val(commit)

    output:
    tuple val(context), path('source'),
        emit: source

    script:
    assert repository != null :
        "Git repository must be specified"

    assert commit?.toString() ==~ /(?i)[0-9a-f]{40,64}/ :
        "Expected a full Git commit hash"

    def clone = new CommandBuilder('git').add('clone', '--no-checkout', repository, 'source')

    def checkout = new CommandBuilder('git').add('-C', 'source', 'checkout', '--detach', commit)

    def submodules = new CommandBuilder('git').add('-C', 'source', 'submodule','update', '--init', '--recursive')

    def script = new ScriptBuilder()
        .addCommand(clone)
        .addCommand(checkout)
        .addCommand(submodules)

    return script.build()
}
