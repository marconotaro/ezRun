% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/util.R
\name{isError}
\alias{isError}
\title{Tests if x contains an error}
\usage{
isError(x)
}
\arguments{
\item{x}{any R object, but only an error in a list can be found.}
}
\value{
Returns FALSE or TRUE.
}
\description{
Returns TRUE if x is a list with at least one element called error.
}
\examples{
isError("error")
isError(list(a=3:5,error=3))
isError(list(errrrror=3))
}
\author{
Rehrauer, Hubert

Schmid, Peter
}
