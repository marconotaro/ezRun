% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/util.R
\name{ezSplitLongLabels}
\alias{ezSplitLongLabels}
\alias{ezSplitLongText}
\title{Splits long labels into two lines}
\usage{
ezSplitLongLabels(labels, nSplit = 20)

ezSplitLongText(text, nSplit = 180)
}
\arguments{
\item{labels}{a character vector to split long elements from.}

\item{nSplit}{an integer specifying at which position to split the labels.}
}
\description{
Splits long labels into two lines.
}
\section{Functions}{
\itemize{
\item \code{ezSplitLongText()}: Splits long character lines into several.

}}
\examples{
a = paste(letters[1:22], collapse="")
b = paste(letters[1:23], collapse="")
c = paste(letters[1:24], collapse="")
charVec = c(a, b, c)
par(mar=c(10.1, 4.1, 4.1, 2.1))
plot(1:3, xaxt="n", xlab="")
splittedLabels = ezSplitLongLabels(charVec, nSplit=22)
axis(1, at=1:3, labels=splittedLabels, las=2)
}
\author{
Rehrauer, Hubert

Schmid, Peter
}
