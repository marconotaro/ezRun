###################################################################
# Functional Genomics Center Zurich
# This code is distributed under the terms of the GNU General
# Public License Version 3, June 2007.
# The terms are available here: http://www.gnu.org/licenses/gpl.html
# www.fgcz.ch

ezMethodDiffMethylation <- function(input=NA, output=NA, param=NA){
    library(dmrseq)
    library(BiocParallel)
    library(annotatr)
    library(DSS)
    require(bsseq)
    library(qs2)
    
    setwdNew(basename(output$getColumn("ResultFolder")))
    register(MulticoreParam(param$cores))
    param$extGrouping <- paste0(param$grouping,' [Factor]')
    params <- MulticoreParam(workers = param$cores)
    inputMeta <- input$meta
    sampleGroupInfo <- inputMeta[inputMeta[[param$extGrouping]]== param$sampleGroup,]
    refGroupInfo <- inputMeta[inputMeta[[param$extGrouping]]== param$refGroup,]
    
    files <- c(sampleGroupInfo$`COV [File]`, refGroupInfo$`COV [File]`)
    names(files) <- c(rownames(sampleGroupInfo), rownames(refGroupInfo))
    
    for(j in 1:length(files)){
        system(paste('zcat', file.path(param$dataRoot,files[j]), '>', sub('.gz$', '', basename(files[j]))))
    }
    
    conditions <- c(
        sampleGroupInfo[[param$extGrouping]],
        refGroupInfo[[param$extGrouping]])
    
    # Read the Bismark data into a BSseq object
    bismarkBSseq <- read.bismark(
        files = sub('.gz$', '', basename(files)),
        rmZeroCov = TRUE,
        strandCollapse = TRUE,
        verbose = TRUE
    )
    sampleNames(bismarkBSseq) <- names(files)
    pData(bismarkBSseq)$Condition <- conditions
    
    coverage <- getCoverage(bismarkBSseq, type = "Cov")
    
    # Filter out loci with zero coverage in all samples of any condition
    refGroup_samples <- which(pData(bismarkBSseq)$Condition == param$refGroup)
    sampleGroup_samples <- which(pData(bismarkBSseq)$Condition == param$sampleGroup)
    
    loci_with_coverage <- rowSums(coverage[, refGroup_samples] > 0) > 0 &
        rowSums(coverage[, sampleGroup_samples] > 0) > 0
    
    bismarkBSseq_filtered <- bismarkBSseq[loci_with_coverage, ]
    
    # Filter out non-canonical chromosomes
    chr_names <- levels(seqnames(bismarkBSseq_filtered))
    standard_chrs <- chr_names[nchar(chr_names) < 6]
    
    # Keep only loci on standard chromosomes
    bismarkBSseq_filtered <- bismarkBSseq_filtered[as.character(seqnames(bismarkBSseq_filtered)) %in% standard_chrs, ]
    
    # Perform differential methylation analysis
    regions <- dmrseq(
        bs = bismarkBSseq_filtered,
        testCovariate = "Condition",
        BPPARAM = params
    )
    
    blocks <- dmrseq(
        bs = bismarkBSseq_filtered,
        cutoff = param$qVal,
        testCovariate = "Condition",
        block = TRUE,
        minInSpan = 500,
        bpSpan = 5e4,
        maxGapSmooth = 1e6,
        maxGap = 5e3
    )
    
    #Run DSS
    dmlTest.sm = DMLtest(bismarkBSseq_filtered, group1=rownames(pData(bismarkBSseq_filtered))[pData(bismarkBSseq_filtered)$Condition  %in% param$sampleGroup], group2=rownames(pData(bismarkBSseq_filtered))[pData(bismarkBSseq_filtered)$Condition  %in% param$refGroup], smoothing = TRUE)
    dmlResults <- list()
    dmlResults[['dmls']] = callDML(dmlTest.sm, delta=param$minDelta, p.threshold=param$qVal_perSite)
    dmlResults[['dmls']] = dmlResults[['dmls']][dmlResults[['dmls']]$fdr <= param$qVal_perSite,]
    dmlResults[['dmrs']] = callDMR(dmlTest.sm, delta=param$minDelta, p.threshold=param$qVal)
    
    
    # Export results:
    qs_save(dmlTest.sm, paste0('dmlTest_',param$sampleGroup,'_vs_', param$refGroup, '.qs2'))
    qs_save(dmlResults, paste0('dss_results.qs2'))
    qs_save(bismarkBSseq_filtered, file = "bismarkBSseq_filtered.qs2")
    qs_save(regions, file = "dmrseq_results.qs2")
    qs_save(blocks, file = "large_blocks.qs2")
    qs_save(param, file = 'param.qs2')
    
    ##Create RMD Report 
    makeRmdReport(param=param, rmdFile = "DiffMethylation.Rmd")
    return('success')  
}

EzAppDiffMethylation <-
    setRefClass("EzAppDiffMethylation",
                contains = "EzApp",
                methods = list(
                    initialize = function()
                    {
                        "Initializes the application using its specific defaults."
                        runMethod <<- ezMethodDiffMethylation
                        name <<- "EzAppDiffMethylation"
                        appDefaults <<- rbind(qVal=ezFrame(Type="numeric", DefaultValue=0.05, Description="fdr cutoff"),
                                              qVal_perSite=ezFrame(Type="numeric", DefaultValue=0.001, Description="fdr cutoff per site"),
                                              minDelta=ezFrame(Type="numeric", DefaultValue=0.1, Description="minimum delta methylation difference")
                        )
                    }
                )
    )
