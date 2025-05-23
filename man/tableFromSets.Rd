% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/util.R
\name{tableFromSets}
\alias{tableFromSets}
\title{Creates a contingency table from a list of vectors.}
\usage{
tableFromSets(setList)
}
\arguments{
\item{setList}{a named list of two or three elements.}
}
\description{
The list should contain two or three elements.
}
\examples{
aList = list(a=1:5,b=3:6)
tableFromSets(aList)
}
\author{
Rehrauer, Hubert

Schmid, Peter
}
