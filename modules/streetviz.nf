/**
 * Renders a geographic graph using Streetviz.  
 *
 * **Inputs**  
 * `key`: Caller-supplied key, passed through unchanged.  
 * `graph`: Input graph in unweighted, undirected METIS format.  
 * `coords`: Input coordinates in vertex order.  
 * `edge_marks`: Optional edge groups, one `u v group` per line (`[]` if omitted).  
 * `node_marks`: Optional node groups, one `vertex group` per line (`[]` if omitted).  
 * `groups`: Optional group labels and colors in JSON format (`[]` if omitted).  
 * `opts`: Map of rendering parameters.  
 *
 * **Required parameters (`opts`)**  
 * `coord_format`: Coordinate format, `lonlat` or `dimacs10-osm`.  
 *
 * **Optional parameters (`opts`)**  
 * `mark_id_base`: Vertex ID base in the marking files, `0` or `1` (default: 1).  
 * `basemap`: Basemap type, `osm`, `none`, or `custom` (default: osm).  
 * `tile_url`: HTTPS raster tile URL template, required for a custom basemap.  
 * `attribution`: Tile provider attribution, required for a custom basemap.  
 *
 * Omitted optional parameters use the executable's defaults.  
 *
 * **Outputs**  
 * `report`: Interactive HTML map (`map.html`).  
 * `log`: Combined stdout and stderr (`streetviz.log`).  
 * Both outputs retain the original `key`.  
 *
 * **Requirements**  
 * The `streetviz` executable must be available on `PATH` in the execution environment.  
 */
process STREETVIZ {
    label 'visualization'
    cache params.get('cache_streetviz', true)

    input:
    tuple val(key),
        path(graph, stageAs: 'graph/*'),
        path(coords, stageAs: 'coords/*'),
        path(edge_marks, stageAs: 'edge_marks/*'),
        path(node_marks, stageAs: 'node_marks/*'),
        path(groups, stageAs: 'groups/*'),
        val(opts)

    output:
    tuple val(key), path('map.html'), emit: report
    tuple val(key), path('streetviz.log'), emit: log

    script:
    assert opts.coord_format != null : "Streetviz requires coord_format"

    def command = new util.CommandBuilder('streetviz')
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

    return new util.ScriptBuilder()
        .addCommand(command, 'streetviz.log', true)
        .build()
}
