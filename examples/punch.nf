include { PUNCH_FILTER } from '../modules/punchfilter.nf'

params {
    source_path = "${env('HOME')}/Programming/data/belgium.osm.graph"
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