process STRIP_TO_EDGE_PAIRS {
    label 'filtering'

    input:
    tuple val(context), path(edges)

    output:
    tuple val(context), path('edge_pairs.txt'),
        emit: metadata

    script:
    def command = new CommandBuilder('awk')
        .add('{print $1, $2}', edges)
        .addUnwrapped('>')
        .add('edge_pairs.txt')

    return new ScriptBuilder()
        .addCommand(command)
        .build()
}