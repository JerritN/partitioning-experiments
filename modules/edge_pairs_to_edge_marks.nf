process EDGE_PAIRS_TO_EDGE_MARKS {
    label 'visualization'

    input:
    tuple val(context), path(edge_pairs)

    output:
    tuple val(context), path('edge_marks.txt'),
        emit: metadata

    script:
    def command = new CommandBuilder('awk')
        .add('{print $1, $2, 0}', edge_pairs)
        .addUnwrapped('>')
        .add('edge_marks.txt')

    return new ScriptBuilder()
        .addCommand(command)
        .build()
}