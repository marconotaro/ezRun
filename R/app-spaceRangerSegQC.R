###################################################################
# Functional Genomics Center Zurich
# This code is distributed under the terms of the GNU General
# Public License Version 3, June 2007.
# The terms are available here: http://www.gnu.org/licenses/gpl.html
# www.fgcz.ch

EzAppSpaceRangerSegQC <-
  setRefClass("EzAppSpaceRangerSeqQC",
              contains = "EzApp",
              methods = list(
                initialize = function()
                {
                  "Initializes the application using its specific defaults."
                  runMethod <<- ezMethodSpaceRangerSegQC
                  name <<- "EzAppSpaceRangerSegQC"
                }
              )
  )

ezMethodSpaceRangerSegQC <- function(input=NA, output=NA, param=NA){
  sampleName <- input$getNames()
  cmd <- paste("spaceranger segment", paste0("--id=", sampleName),
                                      paste0("--localmem=", param$ram),
                                      paste0("--localcores=", param$cores))
  
  cmd <- paste(cmd, paste0("--tissue-image=", input$getFullPaths("Image")))
  
  if(ezIsSpecified(param$cmdOptions)){
    cmd <- paste(cmd, param$cmdOptions)
  }
  ezSystem(cmd)
  ezSystem(paste("mv", file.path(sampleName, "outs"), "result"))
  unlink(sampleName, recursive=TRUE)
  file.rename('result',  sampleName)
  ezSystem(paste("mv", file.path(sampleName, "websummary.html"), file.path(sampleName, "web_summary.html")))
  
  return("Success")
}
