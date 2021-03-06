normalizeBatch <- function(batch.x, batch.comp, mode="range", p=0.01, target=NULL, markers=NULL, ...)
# Performs warp- or range-based adjustment of different batches, given a 
# list of 'x' objects like that used for 'prepareCellData'
# and another list specifying the composition of samples per batch.
#
# written by Aaron Lun
# created 27 October 2016
# last modified 18 August 2017
{
    if (is.null(batch.comp)) {
        batch.comp <- lapply(batch.x, function(i) rep(1, length(i)))
    }
    all.levels <- unique(unlist(batch.comp))
    batch.comp <- lapply(batch.comp, factor, levels=all.levels)
    nbatches <- length(batch.x)
    if (nbatches!=length(batch.comp)) {
        stop("length of 'batch.x' and 'batch.comp' must be identical")
    }

    # Checking the number of markers we're dealing with.
    batch.out <- vector("list", nbatches)
    for (b in seq_len(nbatches)) { 
        out <- .pull_out_data(batch.x[[b]])

        if (!is.null(markers)) {
            mm <- match(markers, out$markers)
            if (any(is.na(mm))) { stop("some 'markers' not present in batch") }
            out$markers <- out$markers[mm]
            out$exprs <- lapply(out$exprs, function(x) { x[,mm,drop=FALSE] })
        }
        batch.out[[b]] <- out

        if (b==1L) {
            ref.markers <- out$markers
        } else if (!identical(ref.markers, out$markers)) { 
            stop("markers are not identical between batches")
        }
        if (length(out$samples)!=length(batch.comp[[b]])) {
            stop("corresponding elements of 'batch.comp' and 'batch.x' must have same lengths")
        }
    }

    # Expanding possible modes.    
    mode <- rep(mode, length.out=length(ref.markers))
    if (is.null(names(mode))) {
        names(mode) <- ref.markers
    }

    # Checking 'target' specification.
    if (!is.null(target)) { 
        target <- as.integer(target)
        if (target < 1L || target > nbatches) {
            stop("'target' must be a positive integer no greater than the number of batches")
        }
    }

    # Calculating weights.
    batch.weights <- .computeCellWeights(batch.out, batch.comp)

    # Setting up an output object.
    output <- vector("list", nbatches)
    for (b in seq_len(nbatches)) { 
        cur.out <- batch.out[[b]]
        nsamples <- length(cur.out$samples)

        cur.exprs <- vector("list", nsamples)
        for (s in seq_len(nsamples)) {
            cur.exprs[[s]] <- cur.out$exprs[[s]]
            colnames(cur.exprs[[s]]) <- cur.out$markers
        }
        names(cur.exprs) <- cur.out$samples
        output[[b]] <- cur.exprs 
    }
    names(output) <- names(batch.x)

    for (m in ref.markers) {
        # Putting together observations.
        all.obs <- vector("list", nbatches)
        for (b in seq_len(nbatches)) { 
            cur.out <- batch.out[[b]]
            nsamples <- length(cur.out$exprs)

            cur.obs <- vector("list", nsamples)
            for (s in seq_len(nsamples)) { 
                cur.obs[[s]] <- cur.out$exprs[[s]][,m]
            }
            all.obs[[b]] <- unlist(cur.obs)
        }
        
        curmode <- match.arg(mode[m], c("none", "range", "warp"))
        if (curmode=="none") {
            # Skipping normalization. 
            ;
        } else if (curmode=="warp") { 
            # Performing warp-based normalization to a reference.
            converters <- .transformDistr(all.obs, batch.weights, m, target=target, ...)
        } else if (curmode=="range") {
            converters <- .rescaleDistr(all.obs, batch.weights, target=target, p=p)
        }
        for (b in seq_len(nbatches)) { 
            converter <- converters[[b]]
            cur.out <- batch.out[[b]]
            for (s in seq_along(cur.out$exprs)) {
                output[[b]][[s]][,m] <- converter(cur.out$exprs[[s]][,m])                
            }
        }        
    }
    return(output)
}

.computeCellWeights <- function(batch.out, batch.comp) { 
    # Computing the average number of samples from each batch to use in correction.
    comp.batches <- do.call(rbind, lapply(batch.comp, table))
    ref.comp <- colMeans(comp.batches)
    batch.weight <- t(ref.comp/t(comp.batches))
    empty.factors <- colSums(!is.finite(batch.weight)) > 0
    if (all(empty.factors)) {
        stop("no level of 'batch.comp' is common to all batches")
    }
    use.batches <- colnames(batch.weight)[!empty.factors]

    # Computes sample- and batch-specific case weights to be used for all markers.
    nbatches <- length(batch.out)
    batch.weights <- vector("list", nbatches)

    for (b in seq_len(nbatches)) { 
        cur.comp <- batch.comp[[b]]
        cur.out <- batch.out[[b]]
        cur.weights <- num.cells <- numeric(length(cur.out$exprs))
        
        for (s in seq_along(cur.out$exprs)) {
            sample.level <- as.character(cur.comp[s])
            num.cells[s] <- nrow(cur.out$exprs[[s]])
            if (sample.level %in% use.batches) { 
                cur.weights[s] <- 1/num.cells[s] * batch.weight[b,sample.level]
            }
        }
        batch.weights[[b]] <- rep(cur.weights, num.cells)
    }
    return(batch.weights)
}

.transformDistr <- function(all.obs, all.wts, name, target, ...) {
    # Subsample intensities proportional to weights.
    nbatch <- length(all.obs)
    cur.ffs <- vector("list", nbatch)
    for (b in seq_len(nbatch)) {
        cur.obs <- all.obs[[b]]
        cur.wts <- all.wts[[b]]
        chosen <- sample(cur.obs, length(cur.obs), prob=cur.wts, replace=TRUE)
        chosen <- c(chosen, range(cur.obs)) # Adding also the first and last entries.
        cur.ffs[[b]] <- flowFrame(cbind(M=chosen))
    }        

    names(cur.ffs) <- names(all.obs)
    fs <- as(cur.ffs, "flowSet")
    colnames(fs) <- name
    if (!is.null(target)) { 
        target <- names(cur.ffs)[target]
    }

    # Applying warping normalization, as described in the flowStats vignette.
    norm <- normalization(normFunction=function(x, parameters, ...) { flowStats::warpSet(x, parameters, ...) },
                          parameters=name, arguments=list(monwrd=TRUE, target=target, ...))
    new.fs <- normalize(fs, norm)

    # Defining warp functions (setting warpFuns doesn't really work, for some reason).
    converter <- vector("list", nbatch)
    for (b in seq_len(nbatch)) {
        old.i <- exprs(fs[[b]])[,1]
        new.i <- exprs(new.fs[[b]])[,1]
        converter[[b]] <- splinefun(old.i, new.i)
    }
    return(converter)
}

.rescaleDistr <- function(all.obs, all.wts, target, p) {
    # Computing the average max/min.
    nbatches <- length(all.obs)
    batch.min <- batch.max <- numeric(nbatches)
    for (b in seq_len(nbatches)) { 
        cur.obs <- all.obs[[b]]
        cur.wts <- all.wts[[b]]

        keep <- cur.wts>0
        cur.obs <- cur.obs[keep]
        cur.wts <- cur.wts[keep]

        o <- order(cur.obs)
        cur.obs <- cur.obs[o]
        cur.wts <- cur.wts[o]

        # Taking the midpoint of each step, rather than the start/end points. 
        mid.cum.weight <- cumsum(cur.wts) - cur.wts/2
        total.weight <- sum(cur.wts)
        
        # Getting the left/right extreme.
        out <- approx(mid.cum.weight/total.weight, cur.obs, xout=c(p, 1-p), rule=2)$y
        batch.min[b] <- out[1]
        batch.max[b] <- out[2]
    }

    # Selecting the target batch to perform the normalization.
    if (is.null(target)) { 
        targets <- c(mean(batch.min), mean(batch.max))
    } else {
        targets <- c(batch.min[target], batch.max[target])
    }

    # Scaling intensities per batch so that the observed range equals the average range.
    converters <- vector("list", nbatches)
    FUNGEN <- function(fit) {
        m <- coef(fit)[2]
        b <- coef(fit)[1]
        function(x) { x * m + b }
    }

    for (b in seq_len(nbatches)) {
        current <- c(batch.min[b], batch.max[b])
        fit <- lm(targets ~ current)
        converters[[b]] <- FUNGEN(fit)
    }
    return(converters)
}
