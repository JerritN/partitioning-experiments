/**
 * Renders a geographic METIS graph with optional edge and node groups.
 * The task environment must provide the streetviz command on PATH.
 *
 * Inputs, in tuple order:
 *   context     Execution context, passed through unchanged.
 *   graph       Unweighted, undirected METIS graph.
 *   coords      Coordinate rows in vertex order.
 *   edge_marks  Optional rows of u v group.
 *   node_marks  Optional rows of vertex group.
 *   groups      Optional group labels and colors in JSON.
 *   opts        Rendering options. Pass [] for each omitted file input.
 *
 * Required option: coord_format (lonlat or dimacs10-osm).
 * Optional options: mark_id_base (0 or 1), basemap (osm, none or custom).
 * A custom basemap takes both tile_url and attribution.
 * Omitted options use Streetviz defaults.
 *
 * Outputs: (context, map.html) and (context, streetviz.log).
 */
process STREETVIZ {
    label 'visualization'

    input:
    tuple val(context),
        path(graph, stageAs: 'graph/*'),
        path(coords, stageAs: 'coords/*'),
        path(edge_marks, stageAs: 'edge_marks/*'),
        path(node_marks, stageAs: 'node_marks/*'),
        path(groups, stageAs: 'groups/*'),
        val(opts)

    output:
    tuple val(context), path('map.html'), emit: report
    tuple val(context), path('streetviz.log'), emit: log

    script:
    assert opts.coord_format != null : "Streetviz requires coord_format"

    def command = new CommandBuilder('streetviz')
        .add('--graph', graph)
        .add('--coords', coords)
        .add('--coord-format', opts.coord_format)
        .add('--output', 'map.html')
        .addIf(edge_marks as boolean, '--edge-marks', edge_marks)
        .addIf(node_marks as boolean, '--node-marks', node_marks)
        .addIf(groups as boolean, '--groups', groups)
        .addIf(opts.mark_id_base != null, '--mark-id-base', opts.mark_id_base)
        .addIf(opts.basemap != null, '--basemap', opts.basemap)
        .addIf(opts.tile_url != null, '--tile-url', opts.tile_url)
        .addIf(opts.attribution != null, '--attribution', opts.attribution)

    return new ScriptBuilder()
        .addCommand(command, 'streetviz.log', true)
        .build()
}
