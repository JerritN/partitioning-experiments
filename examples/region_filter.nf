include { REGION_FILTER } from '../modules/region_filter.nf'

params {
    source_path = "${params.data_path}/belgium.osm.graph"
}

workflow {
    main:
    opts = [
        U: 1000,
        region_factor: 0.5,
        regions: 100,
        rounds: 3,
        min_rounds: 2,
        terminals: 'far',
        centers: 'spread',
        seed: 42,
        dump_pairs: 'auto'
    ]

    REGION_FILTER(
        tuple(
            'region_test',
            file(params.source_path),
            opts
        )
    )

    publish:
    logs = REGION_FILTER.out.log
    graphs = REGION_FILTER.out.graph
}

output {
    logs {
        path 'logs'
    }

    graphs {
        path 'graphs'
    }
}