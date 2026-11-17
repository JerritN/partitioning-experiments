include { GIT_CHECKOUT } from '../modules/git_checkout.nf'
include { CMAKE_BUILD } from '../modules/cmake_build.nf'
include { REGION_FILTER } from '../modules/region_filter.nf'
include { CUT_EDGES_TO_METADATA } from '../modules/cut_edges_to_metadata.nf'
include { MT_KAHYPAR } from '../modules/mt_kahypar.nf'

params {
    repository: String = "${params.project_path}/mt-kahypar"
    kahypar_commit: String = "085bdae"
    region_filter_commit: String = "7467201"
    graph_dir: String = "${params.project_path}/data"
    region_filter_u: Integer = 1000
    mt_kahypar_blocks: Integer = 8
    mt_kahypar_epsilon: Float = 0.03
    mt_kahypar_objective: String = "cut"
    mt_kahypar_preset_type: String = "default"
}

workflow {
    main:
    // 1. Checkout the requested Git commits for Mt-KaHyPar and RegionFilter
    def kahyparCommitHash = GitUtils.resolveCommit(
        params.repository,
        params.kahypar_commit
    )
    def regionFilterCommitHash = GitUtils.resolveCommit(
        params.repository,
        params.region_filter_commit
    )
    def checkoutInputs = channel.from([
        tuple([commit: kahyparCommitHash, tool: 'kahypar'], params.repository, kahyparCommitHash),
        tuple([commit: regionFilterCommitHash, tool: 'regionFilter'], params.repository, regionFilterCommitHash)
    ])

    GIT_CHECKOUT(checkoutInputs)
    def sources = GIT_CHECKOUT.out.source

    // 2. Build Mt-KaHyPar and RegionFilter from the checked-out sources
    def kahyparBuildOpts = [
        preset: 'minimal',
        target: 'MtKaHyPar',
        binary: params.mt_kahypar.mt_kahypar_binary,
        threads: 8
    ]
    def regionFilterBuildOpts = [
        preset: 'minimal',
        target: 'RegionFilter',
        binary: params.mt_kahypar.region_filter_binary,
        threads: 8
    ]
    def buildOpts = [
        kahypar: kahyparBuildOpts,
        regionFilter: regionFilterBuildOpts
    ]
    def buildInputs = sources.map { context, source ->
        def opts = buildOpts[context.tool]
        tuple(context + [build_opts: opts], source, opts)
    }

    CMAKE_BUILD(buildInputs)
    def binaries = CMAKE_BUILD.out.binary.branch { context, _binary ->
        kahypar: context.tool == 'kahypar'
        regionFilter: context.tool == 'regionFilter'
    }
    def kahyparExecutable = binaries.kahypar
        .map { _context, binary -> binary }
    def regionFilterExecutable = binaries.regionFilter
        .map { _context, binary -> binary }

    // 3. Load graph files
    def graphPath = file(params.graph_dir, checkIfExists: true)
    def graphs = channel.fromPath(
        graphPath.isDirectory() ? "${graphPath}/*.graph" : graphPath,
        checkIfExists: true
    ).map { graph ->
        tuple([graph: graph.baseName, graphFile: graph], graph)
    }
        
    // 4. Run RegionFilter on each graph file
    def regionFilterOpts = channel.value([
        U: params.region_filter_u
    ])
    
    def regionFilterInputs = graphs
        .combine(regionFilterExecutable)
        .combine(regionFilterOpts)
        .map { context, graph, executable, opts ->
            tuple(context + [regionFilterOpts: opts], executable, graph, opts)
        }

    REGION_FILTER(regionFilterInputs)
    def cutEdges = REGION_FILTER.out.cut_edges

    // 5. convert the cut edges to a format suitable for Mt-KaHyPar
    CUT_EDGES_TO_METADATA(cutEdges)
    def naturalEdges = CUT_EDGES_TO_METADATA.out.metadata

    // 6. Run Mt-KaHyPar on the natural edges
    def sharedKahyparOpts = [
        file_format: 'metis',
        edge_metadata_type: 'natural_edge',
        blocks: params.mt_kahypar_blocks,
        epsilon: params.mt_kahypar_epsilon,
        objective: params.mt_kahypar_objective,
        preset_type: params.mt_kahypar_preset_type,
    ]
    def ratingOpts = channel.fromList([
        [c_rating_edge_metadata: 'ignore'],
        [c_rating_edge_metadata: 'skip_natural_edge'],
        [c_rating_edge_metadata: 'natural_edge_contribute_zero'],
        [c_rating_edge_metadata: 'natural_edge_contribute_negative'],
    ])
    def kahyparOpts = ratingOpts.map { ratingOpt ->
        sharedKahyparOpts + ratingOpt
    }
    def kahyparInputs = naturalEdges
        .combine(kahyparExecutable)
        .combine(kahyparOpts)
        .map { context, metadata, executable, opts ->
            tuple(
                context + [kahyparOpts: opts],
                executable,
                context.graphFile,
                [],
                metadata,
                opts
            )
        }
    
    MT_KAHYPAR(kahyparInputs)

    // 7. Publish results
    publish:
    region_log = REGION_FILTER.out.log
    natural_edges = naturalEdges
    kahypar_results = MT_KAHYPAR.out.partition.mix(
        MT_KAHYPAR.out.log,
    )
}

output {
    region_log {
        mode 'copy'
        path { context, file ->
            file >> "${context.graph}/region_filter.log"
        }
    }

    natural_edges {
        mode 'copy'
        path { context, file ->
            file >> "${context.graph}/natural_edges_metadata.txt"
        }
    }

    kahypar_results {
        mode 'copy'
        path { context, file ->
            def rating = context.kahyparOpts.c_rating_edge_metadata
            file >> "${context.graph}/${rating}/${file.name}"
        }
    }
}