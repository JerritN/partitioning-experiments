include { PUNCH_FILTER } from '../modules/punch_filter.nf'

params {
    source_path = "${params.data_path}/belgium.osm.graph"
    U = 1000
}

workflow {
    main:
    opts = [U: params.U, verbose: true]
    PUNCH_FILTER(tuple('punch', params.source_path, opts))
    
    publish:
    log = PUNCH_FILTER.out.log
}

output {
    log {
        path 'log'
    }
}