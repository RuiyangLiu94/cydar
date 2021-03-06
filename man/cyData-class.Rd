\name{CyData-class}
\docType{class}

\alias{CyData}
\alias{CyData-class}
\alias{show,CyData-method}

\title{CyData class and methods}
\description{An overview of the CyData class and applicable methods.}

\usage{
CyData(markerData, intensities=NULL, cellAssignments=NULL,
    cellIntensities=NULL, cellData=NULL, assays=NULL, ...)
}

\arguments{
\item{markerData}{A DataFrame where each row corresponds to a marker, and is named according to that marker.}
\item{intensities}{A numeric matrix of median intensities for each group of cells (row) and each marker (column).}
\item{cellAssignments}{A list of integer vectors specifying which cells are assigned to each group.}
\item{cellIntensities}{A numeric matrix of intensities for each marker (row) and in each cell (column).}
\item{cellData}{A DataFrame containing information about each cell in each row.}
\item{assays, ...}{Arguments to be passed to the \code{SummarizedExperiment} constructor.}
}

\details{
The CyData class is designed to store the cell counts for each group of cells (e.g., hyperspheres, clusters), along with the median intensities for each group.
It inherits from the SummarizedExperiment class and contains the additional slots:
\describe{
\item{markerData}{A DataFrame containing information about each marker in each row.
The row names are used as the marker names.
}
\item{intensities}{A numeric matrix where each row corresponds to a group of cells and each column corresponds to a marker.
Each matrix entry contains the average (usually median) intensity across all cells in a group for a particular marker.
}
\item{cellAssignments}{A list of integer vectors containing column indices of \code{cellIntensities}.
Each vector corresponds to a group and specifies the cells that were assigned to that group.
}
\item{cellIntensities}{A numeric matrix containing intensities for each marker in each individual cell in the experiment.
Each column represents a cell while each row represents a marker.
This column-major setup is more amenable to fast processing later.
}
\item{cellData}{A DataFrame containing information about each cell in each row.
}
}
The above constructor will set \code{intensities} and \code{assays} to a matrix with no rows, if not specified.
It will also set \code{cellIntensities} to a matrix with no columns and \code{cellData} to an empty list by default.
}

\value{
A CyData object containing the specified information.
}

\examples{
# A minimal example.
my.markers <- DataFrame(row.names=LETTERS)
cyd.minimal <- CyData(markerData=my.markers)

# Adding extra detail.
counts <- matrix(rpois(1000, 10), ncol=10)
medians <- matrix(rgamma(1000, 1, 1), ncol=10)
cell.int <- matrix(rgamma(10000, 1, 1), nrow=10)
marker.data <- DataFrame(row.names=LETTERS[1:10])
cell.data <- DataFrame(sample.id=sample(10, 1000, replace=TRUE))
cyd <- CyData(assay=counts, markerData=marker.data, cellData=cell.data,
    intensities=medians, cellIntensities=cell.int)
}

\author{
Aaron Lun
}
