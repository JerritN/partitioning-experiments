process VERTEX_GROUPS_TO_NODE_MARKS {
    label 'visualization'

    input:
    tuple val(context), path(vertex_groups)

    output:
    tuple val(context), path('node_marks.txt'),
        emit: metadata

    script:
    def command = new CommandBuilder('awk')
        .add('{print NR, $1}', vertex_groups)
        .addUnwrapped('>')
        .add('node_marks.txt')

    return new ScriptBuilder()
        .addCommand(command)
        .build()
}