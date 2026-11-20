include { STREETVIZ } from '../modules/streetviz.nf'

// Group requests before joining so one file can satisfy multiple report specs.
// An empty mark file is valid. A missing requested key is an error.
def attachMarks(requests, marks, field) {
    return requests.groupTuple(by: [0, 1])
        .join(marks, by: [0, 1], remainder: true, failOnDuplicate: true)
        .flatMap { graphKey, markKey, reports, marksFile ->
            if (reports == null) return []
            assert marksFile != null : "Missing ${field} for graph ${graphKey}, mark key ${markKey}"
            reports.collect { report -> report + [(field): marksFile] }
        }
}

/**
 * Renders every report specification for each geographic graph.  
 *
 * **Inputs**  
 * `graphs`: Channel of `(graph_key, graph_file, coords_file)` tuples.  
 * `node_marks`, `edge_marks`: Channels of `(graph_key, mark_key, marks_file)` tuples.  
 * `report_specs`: Channel of `(report_key, node_key, edge_key)` tuples shared by all graphs.  
 * `render_opts`: Streetviz option map, including `coord_format`.  
 * Supply unique graph and report keys and one file per requested graph/mark key in each marks channel.  
 *
 * **Outputs**  
 * `reports`, `logs`: Streetviz HTML and logs, each emitted as `(graph_key, report_key, file)`. Both caller-supplied keys pass through unchanged.  
 */
workflow RENDER_GRAPH_REPORTS {
    take:
    graphs
    node_marks
    edge_marks
    report_specs
    render_opts

    main:
    requests = graphs.combine(report_specs).map { graphKey, graph, coords, reportKey, nodeKey, edgeKey ->
        tuple(graphKey, nodeKey, [graphKey: graphKey, reportKey: reportKey,
            graph: graph, coords: coords, edgeKey: edgeKey])
    }
    with_nodes = attachMarks(requests, node_marks, 'nodeMarks')
        .map { report -> tuple(report.graphKey, report.edgeKey, report) }
    render_inputs = attachMarks(with_nodes, edge_marks, 'edgeMarks').map { report ->
        tuple([graph: report.graphKey, report: report.reportKey], report.graph, report.coords, report.edgeMarks, report.nodeMarks, [], render_opts)
    }
    STREETVIZ(render_inputs)

    emit:
    reports = STREETVIZ.out.report.map { key, file -> tuple(key.graph, key.report, file) }
    logs = STREETVIZ.out.log.map { key, file -> tuple(key.graph, key.report, file) }
}
