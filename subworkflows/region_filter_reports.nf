include { REGION_FILTER } from '../modules/region_filter.nf'
include { REGION_ROUND_MARKS } from '../modules/region_round_marks.nf'
include { STREETVIZ } from '../modules/streetviz.nf'

/**
 * Runs RegionFilter and renders the Voronoi cells and retained natural edges of each round.  
 *
 * **Inputs**  
 * `inputs`: Channel of `(context, executable, graph, coords, filter_opts, render_opts)` tuples.  
 * `context`: Unique map per filter run. The report context adds the zero-based `round` field.  
 * `graph`: Original METIS graph with matching `coords`.  
 * `filter_opts`: RegionFilter parameters.  
 * `render_opts`: Streetviz parameters including `coord_format`. Generated markings use 1-based vertex IDs.  
 *
 * **Behavior**  
 * Runs RegionFilter once per input and reads the round count from the first row of `regions.txt`.  
 * Each report uses its round's region column and the retained edges carrying that round's mask bit.  
 * Supports up to 31 rounds. RegionFilter shares bit 30 among all rounds from index 30 onward.  
 *
 * **Outputs**  
 * `reports`: Interactive maps as `(context + [round: r], map.html)`.  
 * `report_logs`: Streetviz logs with the same round context.  
 * `graph`, `mapping`, `regions`, `cut_edges`, `pairs`, `filter_log`: Original RegionFilter outputs and contexts.  
 *
 * **Requirements**  
 * The supplied RegionFilter executable and the Streetviz command must be available to their tasks.  
 */
workflow REGION_FILTER_REPORTS {
    take:
    inputs

    main:
    filter_inputs = inputs.map { context, executable, graph, coords, filter_opts, render_opts ->
        tuple(context, executable, graph, filter_opts)
    }
    render_data = inputs.map { context, executable, graph, coords, filter_opts, render_opts ->
        assert !context.containsKey('round') : "The report context reserves the round field"
        assert render_opts.mark_id_base == null || render_opts.mark_id_base == 1 :
            "RegionFilter report markings use 1-based vertex IDs"
        tuple(context, graph, coords, render_opts)
    }

    REGION_FILTER(filter_inputs)
    round_inputs = REGION_FILTER.out.regions
        .join(REGION_FILTER.out.cut_edges, failOnDuplicate: true, failOnMismatch: true)
        .flatMap { context, regions, cut_edges ->
            def count = regions.withReader { reader -> reader.readLine()?.tokenize()?.size() }
            assert count && count <= 31 :
                "Expected 1 to 31 region columns for ${context}; found ${count ?: 0}"
            (0..<count).collect { r -> tuple(context, r, regions, cut_edges) }
        }

    REGION_ROUND_MARKS(round_inputs)
    render_inputs = REGION_ROUND_MARKS.out.marks
        .combine(render_data, by: 0)
        .map { context, round, edge_marks, node_marks, graph, coords, opts ->
            tuple(context + [round: round], graph, coords, edge_marks, node_marks, [], opts)
        }
    STREETVIZ(render_inputs)

    emit:
    reports = STREETVIZ.out.report
    report_logs = STREETVIZ.out.log
    graph = REGION_FILTER.out.graph
    mapping = REGION_FILTER.out.mapping
    regions = REGION_FILTER.out.regions
    cut_edges = REGION_FILTER.out.cut_edges
    pairs = REGION_FILTER.out.pairs
    filter_log = REGION_FILTER.out.log
}
