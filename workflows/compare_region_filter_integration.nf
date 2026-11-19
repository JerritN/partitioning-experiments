include { GIT_CHECKOUT } from '../modules/git_checkout.nf'
include { CMAKE_BUILD } from '../modules/cmake_build.nf'
include { REGION_FILTER } from '../modules/region_filter.nf'
include { TAKE_COLUMNS } from '../modules/take_columns.nf'
include { MT_KAHYPAR } from '../modules/mt_kahypar.nf'
include { APPEND_TO_ROWS } from '../modules/append_to_rows.nf'
include { INDEX_ROWS } from '../modules/index_rows.nf'
include { STREETVIZ } from '../modules/streetviz.nf'

params {
    // Use with -resume; set a stage to false to rerun its tasks.
    cache_git_checkout: Boolean = true
    cache_cmake_build: Boolean = true
    cache_region_filter: Boolean = true
    cache_mt_kahypar: Boolean = true
    cache_streetviz: Boolean = true

    repository: String = "${params.project_path}/mt-kahypar"
    kahypar_commit: String = "085bdae"
    region_filter_commit: String = "7467201"
    build_threads: Integer = 8
    graph_dir: String = "${params.project_path}/data"
    region_filter_u: Integer = 1000
    mt_kahypar_threads: Integer = 8
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
        definitions: [
            KAHYPAR_ENABLE_GRAPH_PARTITIONING_FEATURES: true
        ],
        target: 'MtKaHyPar',
        binary: params.mt_kahypar.mt_kahypar_binary,
        threads: params.build_threads
    ]
    def regionFilterBuildOpts = [
        preset: 'minimal',
        target: 'RegionFilter',
        binary: params.mt_kahypar.region_filter_binary,
        threads: params.build_threads
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
    TAKE_COLUMNS(cutEdges, [1, 2])
    def naturalEdges = TAKE_COLUMNS.out.output

    // 6. Run Mt-KaHyPar on the natural edges
    def sharedKahyparOpts = [
        file_format: 'metis',
        edge_metadata_type: 'natural_edge',
        threads: params.mt_kahypar_threads,
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

    // 7. Render each partition with the natural edges from its RegionFilter run
    APPEND_TO_ROWS(naturalEdges, 0)
    def edgeMarks = APPEND_TO_ROWS.out.metadata.map { context, marks ->
        tuple(context.graphFile, context.regionFilterOpts, marks)
    }

    INDEX_ROWS(MT_KAHYPAR.out.partition, 1)
    def nodeMarks = INDEX_ROWS.out.output.map { context, marks ->
        tuple(context.graphFile, context.regionFilterOpts, context, marks)
    }
    def renderInputs = nodeMarks
        .combine(edgeMarks, by: [0, 1])
        .map { graph, _filterOpts, context, nodes, edges ->
            def xyz = graph.resolveSibling("${graph.baseName}.xyz")
            def coords = xyz.exists() ? xyz : file("${xyz}.bz2", checkIfExists: true)
            tuple(context, graph, coords, edges, nodes, [], [coord_format: 'dimacs10-osm'])
        }

    STREETVIZ(renderInputs)

    // 8. Publish results
    publish:
    region_log = REGION_FILTER.out.log
    natural_edges = naturalEdges
    kahypar_results = MT_KAHYPAR.out.partition.mix(
        MT_KAHYPAR.out.log,
        STREETVIZ.out.report,
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
            file >> "${context.graph}/${context.kahyparOpts.c_rating_edge_metadata}/${file.name}"
        }
    }
}