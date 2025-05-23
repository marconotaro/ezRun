###################################################################
# Functional Genomics Center Zurich
# This code is distributed under the terms of the GNU General
# Public License Version 3, June 2007.
# The terms are available here: http://www.gnu.org/licenses/gpl.html
# www.fgcz.ch

ezMethodCellRanger <- function(input = NA, output = NA, param = NA) {
  sampleName <- input$getNames()
  sampleDirs <- sort(getFastqDirs(input, "RawDataDir",sampleName))
 
  #1. extract tar files if they are in tar format
  if (all(grepl("\\.tar$", sampleDirs))) {
    runDirs <- tarExtract(sampleDirs, prependUnique=TRUE)
  } else {
    stop("Require inputs to be provided in .tar files.")
  }
  
  #1.1 check validity of inputs
  runDirs <- normalizePath(runDirs)
  
  fileLevelDirs <- normalizePath(list.files(path=runDirs, full.names=TRUE))
  if (any(fs::is_file(fileLevelDirs))) {
    stop(sprintf("Fastq files need to nested inside a folder sharing the samplename. Offending samples: %s", 
                 paste(fileLevelDirs[fs::is_file(fileLevelDirs)], collapse=", ")))
  }
  
  #2. Subsample if chosen
  if (ezIsSpecified(param$nReads) && param$nReads > 0)
    fileLevelDirs <- sapply(fileLevelDirs, subsample, param)
  
  #2.1 Fix FileNames if sampleName in dataset was changed
  cwd <- getwd()
  if(any(basename(fileLevelDirs) != sampleName)) {
    for (fileLevelDir in fileLevelDirs) {
      setwd(fileLevelDir)
      cmd <- paste('rename', 
                   paste0('s/', basename(fileLevelDir),'/',sampleName, '/g'), 
                   paste0(basename(fileLevelDir),'*.gz'))
      ezSystem(cmd)
    }
    setwd(cwd)
  }
  
  fileLevelDir <- paste(fileLevelDirs, collapse = ",")
  cellRangerFolder <- str_sub(sampleName, 1, 45) %>% str_c("-cellRanger")
  
  #3.Generate the cellranger command with the required arguments
  switch(param$TenXLibrary,
         GEX = {
           #3.1. Obtain GEX the reference
           refDir <- getCellRangerGEXReference(param)
           #3.2. Command
           cmd <- paste(
             "cellranger count", paste0("--id=", cellRangerFolder),
             paste0("--transcriptome=", refDir),
             paste0("--fastqs=", fileLevelDir),
             paste0("--sample=", sampleName),
             paste0("--localmem=", param$ram),
             paste0("--localcores=", param$cores),
             paste0("--chemistry=", param$chemistry),
             if(grepl('^[89]', basename(param$CellRangerVersion))){paste0("--create-bam true")},
             if (ezIsSpecified(param$expectedCells)) {paste0("--expect-cells=", param$expectedCells)},
             ifelse(ezIsSpecified(param$includeIntrons) && param$includeIntrons, "--include-introns=true", "--include-introns=false")
           )
         },
         VDJ = {
           #3.1. Obtain the VDJ reference
           refDir <- getCellRangerVDJReference(param)
           #3.2. Command
           cmd <- paste(
             "cellranger vdj", paste0("--id=", cellRangerFolder),
             paste0("--reference=", refDir),
             paste0("--fastqs=", fileLevelDir),
             paste0("--sample=", sampleName),
             paste0("--localmem=", param$ram),
             paste0("--localcores=", param$cores)
           )
         },
         FeatureBarcoding = {
           #3.1. Obtain GEX the reference
           refDir <- getCellRangerGEXReference(param)
           
           #3.2. Locate the Feature sample
           featureDirs <- getFastqDirs(input, "FeatureDataDir", sampleName)
           featureName <- gsub(".tar", "", basename(featureDirs))
           
           #3.3. Locate the Feature info csv file
           featureRefFn <- file.path(
             dirname(featureDirs),
             str_c(sampleName, "feature_ref.csv", sep = "_")
           )
           stopifnot(any(file.exists(featureRefFn)))
           featureRefFn <- head(featureRefFn[file.exists(featureRefFn)], 1)
           
           #3.4. Decompress the sample that contains the antibodies reads if they are in tar format
           if (all(grepl("\\.tar$", featureDirs)))
             featureDirs <- tarExtract(featureDirs)
           
           featureDirs <- normalizePath(featureDirs)
           
           #3.5. Create library file that contains the sample and feature dirs location
           libraryFn <- createLibraryFile(fileLevelDirs, featureDirs, sampleName, featureName)
           
           #3.6. Command
           cmd <- paste(
             "cellranger count", paste0("--id=", cellRangerFolder),
             paste0("--transcriptome=", refDir),
             paste0("--libraries=", libraryFn),
             paste0("--feature-ref=", featureRefFn),
             paste0("--localmem=", param$ram),
             paste0("--localcores=", param$cores),
             paste0("--chemistry=", param$chemistry),
             if (ezIsSpecified(param$expectedCells)) {paste0("--expect-cells=", param$expectedCells)},
             ifelse(ezIsSpecified(param$includeIntrons) && param$includeIntrons, "--include-introns=true", "--include-introns=false")
           )
         })
  
  #4. Add additional cellranger options if specified
  if (ezIsSpecified(param$cmdOptions)) {
    cmd <- paste(cmd, param$cmdOptions)
  }
  
  #5. Execute the command
  ezSystem(cmd)
  
  #6. Optional run of VeloCyto
  if(param$runVeloCyto){
      gtfFile <- param$ezRef["refFeatureFile"]
      library(Herper)
      out <- tryCatch(local_CondaEnv("gi_velocyto", pathToMiniConda = "/usr/local/ngseq/miniforge3"), error = function(e) NULL)
      cmd <- paste('velocyto run10x', cellRangerFolder, gtfFile, '-@', param$cores)
      ezSystem(cmd)
      ezSystem(paste('mv', file.path(cellRangerFolder,'velocyto'),  file.path(cellRangerFolder,'outs')))
  }
  
  #7. Delete temp files and rename the final cellranger output folder
  unlink(dirname(runDirs), recursive = TRUE)
  if (exists("featureDirs")){
    unlink(basename(featureDirs))
  }
  file.rename(file.path(cellRangerFolder, "outs"), sampleName)
  unlink(cellRangerFolder, recursive = TRUE)
  if (ezIsSpecified(param$controlSeqs)) 
    unlink(refDir, recursive = TRUE)
  
  #8. Calculate alignment stats from the BAM file for GEX
  if(param$bamStats && param$TenXLibrary == "GEX"){
    genomeBam <- file.path(sampleName, "possorted_genome_bam.bam")
    if (file.exists(genomeBam)){
      alignStats <- computeBamStatsSC(genomeBam, ram=param$ram)
      if (!is.null(alignStats)){
        ezWrite.table(alignStats, file=file.path(sampleName, "CellAlignStats.txt"), head="Barcode")
      }
    }
  }

  # for GEX libraries
  if(!param$keepAlignment && param$TenXLibrary == "GEX"){
      bamFile <- file.path(sampleName, "possorted_genome_bam.bam")
      if(file.exists(bamFile)){
        ezSystem(paste('rm', bamFile))
        ezSystem(paste('rm', paste0(bamFile,'.bai')))
      }
  } else if(param$keepAlignment && param$TenXLibrary == "GEX"){
      setwd(sampleName)
      bamFile <- "possorted_genome_bam.bam"
      refDir <- param$ezRef["refFastaFile"]
      out <- tryCatch(ezSystem(paste('samtools view', '-T', refDir, '-@', param$cores, '-o', sub('.bam$', '.cram', bamFile), '-C', bamFile)), error = function(e) NULL)
      system('rm possorted_genome_bam.bam')
      setwd('..')
  }
  return("Success")
}

getFastqDirs <- function(input, column, sampleName) {
  fastqDirs <- strsplit(input$getColumn(column), ",")[[sampleName]]
  fastqDirs <- file.path(input$dataRoot, fastqDirs)
  return(fastqDirs)
}

subsample <- function(targetDir, param){
  subDir = paste0(targetDir, "-sub")
  dir.create(subDir)
  fqFiles = list.files(targetDir, pattern = ".fastq.gz", full.names = TRUE, recursive = TRUE)
  stopifnot(length(fqFiles) <= 4) ## subsample commands below do only work if reads are not split in per-lane files
  for (fq in fqFiles){
    fqSub = file.path(subDir, basename(fq))
    cmd = paste("seqtk sample -s 42 -2", fq, param$nReads, "| pigz --fast -p1 >", fqSub)
    ezSystem(cmd)
  }
  return(subDir)
}

createLibraryFile <- function(sampleDirs, featureDirs, sampleName, featureName) {
  libraryFn <- tempfile(pattern = "library", tmpdir = ".", fileext = ".csv")
  libraryTb <- tibble(
    fastqs = c(sampleDirs, featureDirs),
    sample = c(
      rep(sampleName, length(sampleDirs)),
      featureName
    ),
    library_type = c(
      rep("Gene Expression", length(sampleDirs)),
      rep("Antibody Capture", length(featureDirs))
    )
  )
  write_csv(libraryTb, libraryFn)
  return(libraryFn)
}

computeBamStatsSC = function(bamFile, ram=NULL) {
  ## compute stats per cell from the bam file
  if (!is.null(ram)){  
    nAlign = sum(ezScanBam(bamFile, tag = "CB", 
                           what = character(0), isUnmappedQuery = FALSE, countOnly = TRUE)$records)
    if (nAlign / ram > 20e6){
      message("computeBamStatsSC: not executed - would take too much RAM")
      return(NULL)
    }
  }
  cb = ezScanBam(bamFile, tag = "CB", 
                 what = character(0), isUnmappedQuery = FALSE)$tag$CB
  nReads = table(cb)
  resultFrame = data.frame(nRead=as.vector(nReads), row.names=names(nReads))
  x = ezScanBam(bamFile, tag = "UB", 
                what = character(0), isUnmappedQuery = FALSE)$tag$UB
  resultFrame$nUmi = as.vector(tapply(x, cb, n_distinct))
  x = ezScanBam(bamFile, tag = "ts", 
                what = character(0), isUnmappedQuery = FALSE)$tag$ts
  if (length(x) == length(cb)){ ## the 5' protocol does not have the ts tag
    resultFrame$nTso = as.vector(tapply(x > 3, cb, sum, na.rm=TRUE)) ## at least 3 bases
  }
  x = ezScanBam(bamFile, tag = "pa", 
                what = character(0), isUnmappedQuery = FALSE)$tag$pa
  if (length(x) == length(cb)){ ## the 5' protocol does not have the ts tag
    resultFrame$nPa = as.vector(tapply(x > 3, cb, sum, na.rm=TRUE))
  }
  x = ezScanBam(bamFile, tag = "RE", 
                what = character(0), isUnmappedQuery = FALSE)$tag$RE
  resultFrame$nIntergenic = as.vector(tapply(x == "I", cb, sum))
  resultFrame$nExonic = as.vector(tapply(x == "E", cb, sum))
  resultFrame$nIntronic = as.vector(tapply(x == "N", cb, sum))
  return(resultFrame)
}


getCellRangerGEXReference <- function(param) {
  require(rtracklayer)
  cwd <- getwd()
  on.exit(setwd(cwd), add = TRUE)
  
  if (ezIsSpecified(param$controlSeqs) | ezIsSpecified(param$secondRef) | ezIsSpecified(param$extendThreePrime)) {
    refDir <- file.path(getwd(), "10X_customised_Ref")
  } else {
    if (ezIsSpecified(param$transcriptTypes)) {
      cellRangerBase <- paste(sort(param$transcriptTypes), collapse = "-")
      ## This is a combination of transcript types to use.
    } else {
      cellRangerBase <- ""
    }
    refDir <- sub(
      "\\.gtf$", paste0("_10XGEX_SC_", cellRangerBase, "_Index"),
      param$ezRef["refFeatureFile"]
    )
  }
  
  lockFile <- paste0(refDir, ".lock")
  i <- 0
  while (file.exists(lockFile) && i < INDEX_BUILD_TIMEOUT) {
    ### somebody else builds and we wait
    Sys.sleep(60)
    i <- i + 1
  }
  if (file.exists(lockFile)) {
    stop(paste(
      "reference building still in progress after",
      INDEX_BUILD_TIMEOUT, "min"
    ))
  }
  ## there is no lock file
  if (file.exists(refDir)) {
    ## we assume the index is built and complete
    return(refDir)
  }
  
  ## we have to build the reference
  setwd(dirname(refDir))
  ezWrite(Sys.info(), con = lockFile)
  on.exit(file.remove(lockFile), add = TRUE)
  
  job <- ezJobStart("10X CellRanger build")
  
  if (ezIsSpecified(param$controlSeqs)) {
    ## make reference genome
    genomeLocalFn <- tempfile(
      pattern = "genome", tmpdir = getwd(),
      fileext = ".fa"
    )
    file.copy(from = param$ezRef@refFastaFile, to = genomeLocalFn)
    writeXStringSet(getControlSeqs(param$controlSeqs),
                    filepath = genomeLocalFn,
                    append = TRUE
    )
    on.exit(file.remove(genomeLocalFn), add = TRUE)
  } else if(ezIsSpecified(param$secondRef)){
      ## make reference genome
      genomeLocalFn <- tempfile(
          pattern = "genome", tmpdir = getwd(),
          fileext = ".fa"
      )
      file.copy(from = param$ezRef@refFastaFile, to = genomeLocalFn)
      secondaryRef  <- readDNAStringSet(param$secondRef)
      writeXStringSet(secondaryRef,
                      filepath = genomeLocalFn,
                      append = TRUE
      )
      on.exit(file.remove(genomeLocalFn), add = TRUE) 
  } else {
    genomeLocalFn <- param$ezRef@refFastaFile
  }
  
  ## make gtf
  gtfFile <- tempfile(
    pattern = "genes", tmpdir = getwd(),
    fileext = ".gtf"
  )
  if (ezIsSpecified(param$transcriptTypes)) {
    export.gff2(gtfByTxTypes(param, param$transcriptTypes),
                con = gtfFile
    )
  } else {
    file.copy(from = param$ezRef@refFeatureFile, to = gtfFile)
  }
  if (ezIsSpecified(param$controlSeqs)|ezIsSpecified(param$secondRef)) {
    extraGR <- makeExtraControlSeqGR(param)
    gtfExtraFn <- tempfile(
      pattern = "extraSeqs", tmpdir = getwd(),
      fileext = ".gtf"
    )
    on.exit(file.remove(gtfExtraFn), add = TRUE)
    export.gff2(extraGR, con = gtfExtraFn)
    ezSystem(paste("cat", gtfExtraFn, ">>", gtfFile))
  }

  if (ezIsSpecified(param$extendThreePrime)) {
    gtf <- rtracklayer::import(gtfFile)
    seqLengths <- readDNAStringSet(genomeLocalFn)
    seqLengths <- setNames(width(seqLengths), names(seqLengths))
    gtf <- extendGtfThreePrime(gtf, as.integer(param$extendThreePrime), seqLengths)
    rtracklayer::export.gff2(gtf, con=gtfFile)
  }

  cmd <- paste(
    "cellranger mkref",
    "--memgb", param$ram,
    "--localmem", param$ram,
    "--disable-ui",
    paste0("--genome=", basename(refDir)),
    paste0("--fasta=", genomeLocalFn),
    paste0("--genes=", gtfFile),
    paste0("--nthreads=", param$cores)
  )
  ezSystem(cmd)
  file.remove(gtfFile)
  
  return(refDir)
}

getCellRangerVDJReference <- function(param) {
  require(rtracklayer)
  cwd <- getwd()
  on.exit(setwd(cwd), add = TRUE)
  
  refDir <- sub(
    "\\.gtf$", "_10XVDJ_Index",
    param$ezRef["refFeatureFile"]
  )
  
  lockFile <- paste0(refDir, ".lock")
  i <- 0
  while (file.exists(lockFile) && i < INDEX_BUILD_TIMEOUT) {
    ### somebody else builds and we wait
    Sys.sleep(60)
    i <- i + 1
  }
  if (file.exists(lockFile)) {
    stop(paste(
      "reference building still in progress after",
      INDEX_BUILD_TIMEOUT, "min"
    ))
  }
  ## there is no lock file
  if (file.exists(refDir)) {
    ## we assume the index is built and complete
    return(refDir)
  }
  
  ## we have to build the reference
  setwd(dirname(refDir))
  ezWrite(Sys.info(), con = lockFile)
  on.exit(file.remove(lockFile), add = TRUE)
  
  job <- ezJobStart("10X CellRanger build")
  
  cmd <- paste(
    "cellranger mkvdjref",
    paste0("--genome=", basename(refDir)),
    paste0("--fasta=", param$ezRef@refFastaFile),
    paste0("--genes=", param$ezRef@refFeatureFile)
  )
  ezSystem(cmd)
  
  return(refDir)
}

##' @author Opitz, Lennart
##' @template app-template
##' @templateVar method ezMethodCellRanger(input=NA, output=NA, param=NA)
##' @description Use this reference class to run
EzAppCellRanger <-
  setRefClass("EzAppCellRanger",
              contains = "EzApp",
              methods = list(
                initialize = function() {
                  "Initializes the application using its specific defaults."
                  runMethod <<- ezMethodCellRanger
                  name <<- "EzAppCellRanger"
                  appDefaults <<- rbind(
                    TenXLibrary = ezFrame(
                      Type = "charVector",
                      DefaultValue = "GEX",
                      Description = "Which 10X library? GEX or VDJ."
                    ),
                    chemistry = ezFrame(
                      Type = "character",
                      DefaultValue = "auto",
                      Description = "Assay configuration."
                    ),
                    expectedCells = ezFrame(
                      Type = "numeric",
                      DefaultValue = 10000,
                      Description = "Expected number of cells."
                    ),
                    includeIntrons = ezFrame(
                      Type = "logical",
                      DefaultValue = TRUE,
                      Description = "Count reads on introns."
                    ),
                    controlSeqs = ezFrame(
                      Type = "charVector",
                      DefaultValue = "",
                      Description = "control sequences to add"
                    ),
                    bamStats = ezFrame(
                      Type = "logical",
                      DefaultValue = TRUE,
                      Description = "compute per cell alignment stats"
                    ),
                    runVeloCyto = ezFrame(
                        Type = "logical",
                        DefaultValue = FALSE,
                        Description = "run velocyto and generate loom file"
                    ),
                    keepAlignment = ezFrame(
                        Type = "logical",
                        DefaultValue = FALSE,
                        Description = "keep cram/bam file produced by CellRanger"
                    )
                  )
                }
              )
  )
