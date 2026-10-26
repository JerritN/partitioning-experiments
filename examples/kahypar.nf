include { MT_KAHYPAR } from '../modules/mt_kahypar'

params {
    source_path = "${env('HOME')}/Programming/data/belgium.osm.graph"
}

workflow {
    main:
    opts = [
        blocks: 16,
        epsilon: 0.03,
        objective: 'cut',
        preset_type: 'default',
        file_format: 'metis',
        threads: 8,
        seed: 42,
        show_detailed_timings: true,
        enable_progress_bar: true
    ]

    MT_KAHYPAR(
        tuple('baseline', file(params.source_path), [], opts)
    )

    publish:
    partitions = MT_KAHYPAR.out.partition
    logs = MT_KAHYPAR.out.log
}

output {
    partitions {
        path 'partitions'
    }

    logs {
        path 'logs'
    }
}