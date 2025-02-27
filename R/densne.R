#' Density-preserving t-SNE
#'
#' @param X Input data matrix.
#' @param dims Integer output dimensionality.
#' @param perplexity Perplexity parameter (should not be bigger than 
#'  3 * perplexity < nrow(X) - 1).
#' @param theta Speed/accuracy trade-off (increase for less
#'  accuracy), set to 0.0 for exact TSNE 
#' @param verbose Logical; Whether progress updates should be printed 
#' @param max_iter integer; Number of iterations
#' @param Y_init matrix; Initial locations of the objects. If NULL, random
#' initialization will be used 
#' @param stop_lying_iter integer; Iteration after which the perplexities are no
#'  longer exaggerated 
#' @param mom_switch_iter integer; Iteration after which the final momentum is
#'  used
#' @param momentum numeric; Momentum used in the first part of the optimization
#' @param final_momentum numeric; Momentum used in the final part of the 
#'  optimization
#' @param eta numeric; Learning rate
#' @param exaggeration_factor numeric; Exaggeration factor used to multiply the
#'  affinities matrix P in the first part of the optimization
#' @param dens_frac numeric; fraction of the iterations for which the full 
#'  objective function (including the density-preserving term) is used.
#'  For the first \code{1 - dens_frac} fraction of the iterations, only
#'  the original t-SNE objective function is used.
#' @param dens_lambda numeric; the relative importanceof the 
#'  density-preservation term compared to the original t-SNE objective function.
#' @param num_threads Number of threads to be used for parallelisation.
#' @param normalize logical; Should data be normalized internally prior to 
#' distance calculations with \code{\link[Rtsne]{normalize_input}}?
#' @return A numeric matrix corresponding to the t-SNE embedding 
#' @references
#' Density-Preserving Data Visualization Unveils Dynamic Patterns of Single-Cell 
#' Transcriptomic Variability
#' Ashwin Narayan, Bonnie Berger, Hyunghoon Cho;
#' bioRxiv (2020)
#' <doi:10.1101/2020.05.12.077776>
#' @examples 
#' x <- matrix(rnorm(1e3), nrow = 100)
#' d <- densne(x, perplexity = 5)
#' plot(d)
#' @export
densne <- function(
        X,
        dims = 2,
        perplexity = 50,
        theta = 0.5,
        verbose = getOption("verbose", FALSE),
        max_iter = 1000,
        Y_init = NULL,
        stop_lying_iter = if (is.null(Y_init)) 250L else 0L, 
        mom_switch_iter = if (is.null(Y_init)) 250L else 0L, 
        momentum = 0.5,
        final_momentum = 0.8,
        eta = 200,
        exaggeration_factor = 12,
        dens_frac = 0.3,
        dens_lambda = 0.1,
        num_threads = 1,
        normalize = TRUE
    ) {
    X <- as.matrix(X)
    if (normalize) {
      X <- Rtsne::normalize_input(X)
    }
    X <- t(X)
    .check_tsne_params(
        ncol(X),
        dims = dims,
        perplexity = perplexity,
        theta = theta,
        max_iter = max_iter,
        verbose = verbose, 
        Y_init = Y_init,
        stop_lying_iter = stop_lying_iter,
        mom_switch_iter = mom_switch_iter, 
        momentum = momentum,
        final_momentum = final_momentum,
        eta = eta,
        dens_frac = dens_frac,
        dens_lambda = dens_lambda,
        exaggeration_factor = exaggeration_factor
    )
    out <- densne_cpp(
        X = X,
        no_dims = dims,
        perplexity = perplexity,
        theta = theta,
        verbose = verbose,
        max_iter = max_iter,
        Y_in = matrix(),
        init = !is.null(Y_init),
        stop_lying_iter = stop_lying_iter,
        mom_switch_iter = mom_switch_iter,
        momentum = momentum,
        final_momentum = final_momentum,
        eta = eta,
        exaggeration_factor = exaggeration_factor,
        dens_frac = dens_frac,
        dens_lambda = dens_lambda,
        final_dens = FALSE,
        num_threads = num_threads
    )
    t(out)
}


.check_tsne_params <- function(
        nsamples,
        dims,
        perplexity,
        theta,
        max_iter,
        verbose,
        Y_init,
        stop_lying_iter,
        mom_switch_iter,
        dens_lambda,
        dens_frac,
        momentum,
        final_momentum,
        eta,
        exaggeration_factor) {

    # if (!is.wholenumber(dims) || dims < 1 || dims > 3) {
    #     stop("dims should be either 1, 2 or 3")
    # }
    if (!is.wholenumber(max_iter) || !(max_iter>0)) {
        stop("number of iterations should be a positive integer")
    }
    if (!is.null(Y_init) && (nsamples != nrow(Y_init) || ncol(Y_init) != dims)) {
        stop("incorrect format for Y_init")
    }

    if (!is.numeric(perplexity) || perplexity <= 0) {
        stop("perplexity should be a positive number")
    }
    if (!is.numeric(theta) || (theta < 0.0) || (theta > 1.0) ) {
        stop("theta should lie in [0, 1]")
    }
    if (!is.numeric(dens_frac) || (dens_frac < 0.0) || (dens_frac > 1.0) ) {
        stop("dens_frac should lie in [0, 1]")
    }
    if (!is.numeric(dens_lambda) || (dens_lambda < 0.0) || (dens_lambda > 1.0) ) {
        stop("dens_lambda should lie in [0, 1]")
    }
    if (!is.wholenumber(stop_lying_iter) || stop_lying_iter < 0) {
        stop("stop_lying_iter should be a positive integer")
    }
    if (!is.wholenumber(mom_switch_iter) || mom_switch_iter < 0) {
        stop("mom_switch_iter should be a positive integer")
    }
    if (!is.numeric(momentum) || momentum < 0) {
        stop("momentum should be a positive number")
    }
    if (!is.numeric(final_momentum) || final_momentum < 0) {
        stop("final_momentum should be a positive number")
    }
    if (!is.numeric(eta) || eta <= 0) {
        stop("eta should be a positive number")
    }
    if (!is.numeric(exaggeration_factor) || exaggeration_factor <= 0) {
        stop("exaggeration_factor should be a positive number")
    }

    if (nsamples - 1 < 3 * perplexity) {
        stop("perplexity is too large for the number of samples")
    }

    init <- !is.null(Y_init)
    if (init) {
        Y_init <- t(Y_init) # transposing for rapid column-major access.
    } else {
        Y_init <- matrix()
    }

    list(
        no_dims = dims,
        perplexity = perplexity,
        theta = theta,
        max_iter = max_iter,
        verbose = verbose,
        init = init,
        Y_init = Y_init,
        stop_lying_iter = stop_lying_iter,
        mom_switch_iter = mom_switch_iter,
        momentum = momentum,
        final_momentum = final_momentum,
        eta = eta,
        dens_lambda = dens_lambda,
        dens_frac = dens_frac,
        exaggeration_factor = exaggeration_factor
    )
}


is.wholenumber <- function(x, tol = .Machine$double.eps^0.5) {
    abs(x - round(x)) < tol
}
