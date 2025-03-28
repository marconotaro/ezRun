% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/app-targetEnrichmentQC.R
\name{runTEQC}
\alias{runTEQC}
\title{Runs the target enrichment quality control}
\usage{
runTEQC(file, param)
}
\arguments{
\item{file}{a character representing the path to the file containing the reads.}

\item{param}{a list of parameters:
\itemize{
 \item{designFile}{ a file describing the regions selected by the enrichment kit.}
 \item{covUniformityPlot}{ a logical indicating whether to generate plots for coverage uniformity.}
 \item{covTargetLengthPlot}{ a logical indicating whether to generate plots for coverage vs. target length.}
 \item{duplicatesPlot}{ a logical indicating whether to generate plots for duplicates.}
 \item{paired}{ a logical indicating whether the samples are paired.}
}}
}
\description{
Performs a target enrichment quality control and creates reports of the outcome.
}
\author{
Rehrauer, Hubert

Schmid, Peter
}
