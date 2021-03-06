countCells <- function(x, tol=0.5, BPPARAM=SerialParam(), downsample=10, filter=10, naive=FALSE)
# Extracts counts for each cell in a CyTOF experiment, based on the number of surrounding cells 
# from each sample, given a prepared set of expression values for all cells in each sample.
#
# written by Aaron Lun
# created 21 April 2016
# last modified 24 May 2017
{
    on.exit({gc()}) # Getting rid of the temporary objects.
    .check_cell_data(x, check.clusters=!naive)

    sample.id <- cellData(x)$sample.id - 1L # Get to zero indexing.
    cell.id <- cellData(x)$cell.id - 1L
    if (naive) {
        cluster.centers <- cluster.info <- NULL
    } else {
        cluster.centers <- metadata(x)$cluster.centers
        cluster.info <- metadata(x)$cluster.info
    }
    samples <- colnames(x)

    # Scaling the distance by the number of used markers. 
    all.markers <- markernames(x)
    used <- .chosen_markers(markerData(x)$used, all.markers)
    nused <- sum(used)
    distance <- tol * sqrt(nused) 
    if (distance <= 0) {
        warning("setting a non-positive distance to a small offset")
        distance <- 1e-8        
    }
    
    # Getting some other values.
    downsample <- as.integer(downsample)
    chosen <- which((cell.id %% downsample) == 0L) - 1L
    N <- ceiling(length(chosen)/bpworkers(BPPARAM))
    core.assign <- rep(seq_len(bpworkers(BPPARAM)), each=N, length.out=length(chosen))
    allocations <- split(chosen, core.assign)

    # Parallel analysis.
    ci <- .get_used_intensities(x, used)
    out <- bplapply(allocations, FUN=.count_cells, exprs=ci, distance=distance, 
                    cluster.centers=cluster.centers, cluster.info=cluster.info, filter=filter, 
                    BPPARAM=BPPARAM)
    
    out.cells <- lapply(out, "[[", i="cells")
    out.cells <- unlist(out.cells, recursive=FALSE)
    names(out.cells) <- NULL

    out.index <- lapply(out, "[[", i="index")
    out.index <- unlist(out.index, recursive=FALSE)
    names(out.index) <- NULL

    # Computing the associated statistics.
    out.stats <- .Call(cxx_compute_hyperstats, ci, length(samples), sample.id, out.cells)
    out.counts <- out.stats[[1]]
    colnames(out.counts) <- samples
    out.coords <- matrix(NA_real_, length(out.cells), nmarkers(x))
    out.coords[,used] <- out.stats[[2]]
    colnames(out.coords) <- all.markers

    # Ordering them (not strictly necessary, just for historical reasons).
    o <- order(sample.id[out.index], cell.id[out.index])
    out.counts <- out.counts[o,,drop=FALSE]
    rownames(out.counts) <- seq_along(o)
    out.coords <- out.coords[o,,drop=FALSE]
    out.cells <- out.cells[o]
    out.index <- out.index[o]

    all.ncells <- tabulate(sample.id+1L, length(samples))
    output <- new("CyData", x, assays=Assays(list(counts=out.counts)), 
                  intensities=out.coords, cellAssignments=out.cells,
                  elementMetadata=DataFrame(center.cell=out.index)) 
    output$sample.id <- seq_len(ncol(output))
    output$totals <- all.ncells
    metadata(output)$tol <- tol
    return(output)
}

.count_cells <- function(exprs, distance, cluster.centers, cluster.info, curcells, filter) 
# Helper function so that BiocParallel call is self-contained.
{
    out <- .Call(cxx_count_cells, exprs, distance, cluster.centers, cluster.info, curcells)
    if (!is.character(out)) { 
        cells <- out[[1]]
        keep <- out[[2]] >= filter
        return(list(cells=cells[keep], index=curcells[keep]+1L))
    }
    return(out)
}

