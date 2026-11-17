process CUT_EDGES_TO_METADATA {
    label 'filtering'

    input:
    tuple val(context), path(cut_edges)

    output:
    tuple val(context), path('natural_edges_metadata.txt'),
        emit: metadata

    script:
    def command = new CommandBuilder('awk')
        .add('{print $1 + 1, $2 + 1}', cut_edges)
        .addUnwrapped('>')
        .add('natural_edges_metadata.txt')

    return new ScriptBuilder()
        .addCommand(command)
        .build()
}