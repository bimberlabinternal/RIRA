library(RIRA)
library(Seurat)
library(SeuratData)

testthat::context("Classification")

getBaseSeuratData <- function(){
  suppressWarnings(SeuratData::InstallData("pbmc3k"))
  suppressWarnings(data("pbmc3k"))
  seuratObj <- suppressWarnings(pbmc3k)

  return(seuratObj)
}

prepareTrainingData <- function(){
  seuratObj <- getBaseSeuratData()
  set.seed(RIRA::GetSeed())
  toKeep <- sample(1:ncol(seuratObj), size = 2000)[1:1000]
  seuratObj <- subset(seuratObj, cells = colnames(seuratObj)[toKeep])
  
  seuratObj <- Seurat::NormalizeData(seuratObj)
  seuratObj <- Seurat::FindVariableFeatures(seuratObj, nfeatures = 2000)
  seuratObj <- Seurat::ScaleData(seuratObj)
  seuratObj <- Seurat::RunPCA(seuratObj, features = Seurat::VariableFeatures(object = seuratObj))
  seuratObj <- Seurat::FindNeighbors(seuratObj, dims = 1:10)
  seuratObj <- Seurat::FindClusters(seuratObj, resolution = 0.5)
  
  seuratObj <- Seurat::RunUMAP(seuratObj, dims = 1:10)
  print(Seurat::DimPlot(seuratObj, reduction = "umap", label = T))
  print(Seurat::FeaturePlot(seuratObj, features = c("MS4A1", "GNLY", "CD3E", "CD14", "FCER1A", "FCGR3A", "LYZ", "PPBP","CD8A"), label = T))
  
  seuratObj$CellType <- NA
  seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 0] <- 'TorNK' #Naive CD4+ T'
  seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 1] <- 'TorNK' #Memory CD4+'
  seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 2] <- 'Myeloid' #'CD14 Mono'
  seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 3] <- 'B'
  seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 4] <- 'TorNK' #CD8+ T'
  seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 5] <- 'Myeloid' #'FCGR3A Mono'
  seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 6] <- 'TorNK'
  
  # These no longer form clusters after downsample:
  #seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 6] <- 'NK'
  #seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 7] <- 'DC'
  #seuratObj$CellType[seuratObj$RNA_snn_res.0.5 == 8] <- 'Platelet'
  
  return(seuratObj)
}

prepareTestData <- function(){
  seuratObj <- getBaseSeuratData()
  set.seed(RIRA::GetSeed())
  toKeep <- sample(1:ncol(seuratObj), size = 2000)[1001:2000]
  seuratObj <- subset(seuratObj, cells = colnames(seuratObj)[toKeep])
  
  return(seuratObj)
}


test_that("Cell type classification works", {
  fn <- 'seurat3k.rds'
  if (file.exists(fn)) {
    seuratObjTrain <- readRDS(fn)
  } else {
    seuratObjTrain <- prepareTrainingData()  
    saveRDS(seuratObjTrain, file = fn)
  }
  
  RIRA::TrainAllModels(seuratObj = seuratObjTrain, celltype_column = 'CellType', n_cores = 2)
  
  # Use new data:
  seuratObj <- prepareTestData()
  seuratObj <- PredictCellTypeProbability(seuratObj = seuratObj)
  seuratObj <- AssignCellType(seuratObj = seuratObj)
  
  table(seuratObj$Classifier_Consensus_Celltype)
  expected <- list(
    'B' = 104,
    'TorNK' = 609,
    'Myeloid' = 231,
    'Unknown' = 56
  )
  
  for (cellType in names(expected)) {
    testthat::expect_equal(sum(seuratObj$Classifier_Consensus_Celltype == cellType), expected[[cellType]])
  }

  # Test batchSize:
  seuratObj2 <- prepareTestData()
  seuratObj2 <- PredictCellTypeProbability(seuratObj = seuratObj2, batchSize = 38)
  seuratObj2 <- AssignCellType(seuratObj = seuratObj2)
  testthat::expect_equal(0, sum(seuratObj$Classifier_Consensus_Celltype != seuratObj2$Classifier_Consensus_Celltype))
  
  feats <- c("IFI30", "CD7", "CD3E",   "MS4A1", "CD79A",   "VCAN", "MNDA",   "C1QB", "C1QA")
  RIRA::TrainAllModels(seuratObj = seuratObjTrain, celltype_column = 'CellType', n_cores = 2, output_dir = './classifiers2', gene_list = feats)
  
  # Note: this is incredibly slow, so use the feature-limited version:
  RIRA::InterpretModels(output_dir = './classifiers2')
})

