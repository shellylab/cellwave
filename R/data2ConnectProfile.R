#' create a Cellwave objects
#' @param object a Cellwave objects
#' @param probs Set the percentile of gene expression in one celltype to represent mean value, when use.type="median".
#' @param use.type With parameter "median", CellCall set the mean value of gene as zero, when the percentile of gene expression in one celltype below the parameter "probs". The other choice is "mean" and means that we not concern about the percentile of gene expression in one celltype but directly use the mean value.
#' @param pValueCor firlter target gene of TF with spearson, p > pValueCor, default is 0.05
#' @param CorValue firlter target gene of TF with spearson, value > CorValue, default is 0.1
#' @param topTargetCor use topTargetCor of candidate genes which has firlter by above parameters, default is 1, means 100%
#' @param p.adjust gsea pValue of regulons with BH adjusted threshold, default is 0.05
#' @param method "weighted", "max", "mean", of which "weighted" is default. choose the proper method to score downstream activation of ligand-receptor all regulons of given ligand-receptor relation
#' @param Org choose the species source of gene, eg "Homo sapiens", "Mus musculus"
#' @param IS_core logical variable ,whether use reference LR data or include extended datasets
#' @return the result dataframe of \code{cell communication}
#' @importFrom stringr str_split
#' @importFrom stats quantile median
#' @importFrom dplyr filter
#' @importFrom magrittr %>%
#' @importFrom utils read.table head
#' @export

ConnectProfile <- function(object, pValueCor=0.05, CorValue=0.1, topTargetCor=1, method="weighted", p.adjust=0.05, use.type="median", probs = 0.9, Org = 'Homo sapiens', IS_core = TRUE){
  options(stringsAsFactors = F) 

  if(Org == 'Homo sapiens'){
    f.tmp <- system.file("extdata", "new_ligand_receptor_TFs.txt", package="cellcall")
    triple_relation <- read.table(f.tmp, header = TRUE, quote = "", sep = '\t', stringsAsFactors=FALSE)

    if(IS_core){
    }else{
      f.tmp <- system.file("extdata", "new_ligand_receptor_TFs_extended.txt", package="cellcall")
      triple_relation_extended <- read.table(f.tmp, header = TRUE, quote = "", sep = '\t', stringsAsFactors=FALSE)
      triple_relation <- rbind(triple_relation, triple_relation_extended)
    }

    f.tmp <- system.file("extdata", "tf_target.txt", package="cellcall")
    target_relation <- read.table(f.tmp, header = TRUE, quote = "", sep = '\t', stringsAsFactors=FALSE)
  }else if(Org == 'Mus musculus'){
    f.tmp <- system.file("extdata", "new_ligand_receptor_TFs_homology.txt", package="cellcall")
    triple_relation <- read.table(f.tmp, header = TRUE, quote = "", sep = '\t', stringsAsFactors=FALSE)

    if(IS_core){
    }else{
      f.tmp <- system.file("extdata", "new_ligand_receptor_TFs_homology_extended.txt", package="cellcall")
      triple_relation_extended <- read.table(f.tmp, header = TRUE, quote = "", sep = '\t', stringsAsFactors=FALSE)
      triple_relation <- rbind(triple_relation, triple_relation_extended)
    }

    f.tmp <- system.file("extdata", "tf_target_homology.txt", package="cellcall")
    target_relation <- read.table(f.tmp, header = TRUE, quote = "", sep = '\t', stringsAsFactors=FALSE)
  }

  triple_relation$pathway_ID <- NULL
  print(triple_relation[1:4,])
  complex_tmp <- triple_relation$Receptor_Symbol[grep(",",triple_relation$Receptor_Symbol)] %>% unique()
  tmp_complex_symbol <- triple_relation$Receptor_Symbol[grep(",",triple_relation$Receptor_Symbol)] %>% unique() %>% str_split(",") %>% unlist %>% unique()
  all.gene.needed <- unique(as.character(c(triple_relation$Ligand_Symbol, triple_relation$Receptor_Symbol, triple_relation$TF_Symbol, target_relation$TF_Symbol, target_relation$Target_Symbol,tmp_complex_symbol)))
  # triple_relation[1:4,1:4]
  # target_relation[1:4,1:4]
  my_Expr <- object@data$withoutlog
  colnames(my_Expr) <- as.character(object@meta.data$celltype)
  my_Expr[1:4,1:4]
  detect_gene <- rownames(my_Expr)

  expr_set <- my_Expr[intersect(detect_gene, all.gene.needed),]  
  detect_gene <- rownames(expr_set)
  cell_type = unique(colnames(expr_set))
  expr.fc <- object@data$withoutlog[detect_gene,]
  colnames(expr.fc) <- colnames(expr_set)
  
  rm(list=c("object"))

  complex_matrix <- matrix(ncol = length(colnames(expr_set)))
  complex_matrix <- as.data.frame(complex_matrix)
  colnames(complex_matrix) <- colnames(expr_set)
  myrownames <- c()

  complex <- complex_tmp
  if(length(complex)>0){
      for(i in 1:length(complex)){
        i_tmp = strsplit(complex[i], ',')
        # print(i_tmp)
        if( sum(i_tmp[[1]] %in% detect_gene) == length(i_tmp[[1]]) ){
          tmp_df <- expr_set[i_tmp[[1]],]
          tmp_mean <- colMeans(tmp_df)
          tmp_index <- unique(unlist(apply(tmp_df, 1,function(x) {which(x==0)})))
          tmp_mean[tmp_index] <- 0

          # print(res_tmp)
          complex_matrix <- rbind(complex_matrix, tmp_mean)
          myrownames <- c(myrownames, complex[i])
        }
      }

      complex_matrix <- complex_matrix[-1,]

      ## 把complex的联合表达值加上
      if(nrow(complex_matrix) > 0){
        rownames(complex_matrix) <- myrownames
        expr_set <- rbind(expr_set, complex_matrix)
      }
  }

  expr_set <- expr_set[apply(expr_set, 1, function(x){sum(x!=0)})>0,]
  detect_gene <- rownames(expr_set)
  # expr_set[1:4,1:4]

  print("step1: compute means of gene")
  expr_mean <- matrix(nrow = nrow(expr_set), ncol = length(cell_type))
  myColnames <- c()
  for (i in 1:length(cell_type)) {
    myCell <- cell_type[i]
    myMatrix <- expr_set[,colnames(expr_set)==myCell,drop=F]
    if(use.type=="mean"){
      myMatrix_mean <- as.numeric(apply(myMatrix, 1, mean))
    }else if(use.type=="median"){
      quantil.tmp <- as.numeric(apply(myMatrix, 1, function(x){
          quantile(x, probs = probs,names=FALSE)
      }))
      mean.tmp <- rowMeans(myMatrix)
      mean.tmp[which(quantil.tmp==0)]<-0 
      myMatrix_mean <- mean.tmp
    }
    expr_mean[,i] <- myMatrix_mean
    myColnames <- c(myColnames, myCell)
    # print(myCell)
  }
  expr_mean <- data.frame(expr_mean)
  colnames(expr_mean) <- myColnames
  rownames(expr_mean) <- rownames(expr_set)

  expr_mean <- expr_mean[apply(expr_mean, 1, function(x){sum(x!=0)})>0,]
  detect_gene <- rownames(expr_mean)


  if(use.type=="median"){
    fc.list <- mylog2foldChange.diy(inData = expr.fc, cell.type = cell_type, method="median", probs = probs)
  }else{
    fc.list <- mylog2foldChange.diy(inData = expr.fc, cell.type = cell_type, method="mean", probs = probs)
  }

  print("step2: filter tf-gene with correlation, then score regulons")
  tfs_set <- unique(triple_relation$TF_Symbol)
  regulons_matrix <- matrix(data = 0, nrow = length(tfs_set), ncol = length(cell_type))

  regulons_matrix <- as.data.frame(regulons_matrix)
  rownames(regulons_matrix) <- tfs_set
  colnames(regulons_matrix) <- cell_type
  my_minGSSize <- 5

  for (i in cell_type) {
    print(i)
    tf_val <- lapply(tfs_set, function(x) {
      if(x %in% detect_gene){
        targets <- target_relation[which(target_relation$TF_Symbol==x),2]
        targets <- targets[targets %in% detect_gene]
        if(length(targets)<=0){
          return(0)
        }
        corGene_tmp <- getCorrelatedGene(data = expr_set,cell_type = i,tf=x, target_list=targets, pValue=pValueCor, corValue=CorValue,topGene=topTargetCor)
        common_targets_tmp <- intersect(corGene_tmp, targets)
        if(length(common_targets_tmp)==0){
          return(0)
        }

        gene.name.tmp <- common_targets_tmp
        term_gene_list.tmp <- data.frame(term.name=rep(1, length(gene.name.tmp)), gene=gene.name.tmp)

        if(length(gene.name.tmp)<my_minGSSize){
          return(0)
        }

        tryCatch({
          nes.tmp <- getGSEA(term_gene_list = term_gene_list.tmp,
                             FC_OF_CELL = fc.list[[i]], minGSSize=my_minGSSize, maxGSSize=500)
          if(length(nes.tmp@result$NES)>0 & length(nes.tmp@result$p.adjust)>0 & expr_mean[x,i]>0){
            if(nes.tmp@result$p.adjust<p.adjust & nes.tmp@result$NES>0){
              tf.val.enriched <- nes.tmp@result$NES
              return(tf.val.enriched)
            }else{
              return(0)
            }
          }else{
            return(0)
          }
        },error=function(e){
          return(0)
        })

      }else{
        return(0)
      }
    })
    tf_val <- unlist(tf_val)
    regulons_matrix[,i] <- tf_val
    print(sum(tf_val>0))
  }

  gsea.list <- list()
  gsea.genes.list <- list()
  for (i in cell_type) {
    print(i)
    print(length(which(regulons_matrix[,i]!=0)))
    if(length(which(regulons_matrix[,i]!=0))!=0){
      tfs_set.tmp <- tfs_set[which(regulons_matrix[,i]!=0)]
      tf_val.df <- do.call(rbind, lapply(tfs_set.tmp, function(x) {
        targets <- target_relation[which(target_relation$TF_Symbol==x),2]
        targets <- targets[targets %in% detect_gene]
        if(length(targets)<=0){
          return(NULL)
        }

        corGene_tmp <- getCorrelatedGene(data = expr_set,cell_type = i,tf=x, target_list=targets, pValue=pValueCor, corValue=CorValue,topGene=topTargetCor)
        common_targets_tmp <- intersect(corGene_tmp, targets)

        if(length(common_targets_tmp)==0){
          return(NULL)
        }
        # print(length(common_targets_tmp))
        gene.name.tmp <- common_targets_tmp
        if(length(gene.name.tmp)<my_minGSSize){
          return(NULL)
        }

        term_gene_list.tmp <- data.frame(term.name=rep(x, length(gene.name.tmp)), gene=gene.name.tmp)
        return(term_gene_list.tmp)
      }))
      nes.tmp <- getGSEA(term_gene_list = tf_val.df, FC_OF_CELL = fc.list[[i]], minGSSize=my_minGSSize, maxGSSize=500)

      gsea.list <- c(gsea.list, list(nes.tmp))
    }else{
      gsea.list <- c(gsea.list, list(vector()))
    }
  }
  names(gsea.list) <- cell_type


  print("step3: get distance between receptor and tf in pathway")

  DistanceKEGG <- getDistanceKEGG(data = triple_relation,method = "mean")

  print("step4: score downstream activation of ligand-receptor all regulons of given ligand-receptor relation (weighted, max, or mean) ####")
  l_r_inter <- unique(triple_relation[,5:6])
  expr_r_regulons <- matrix(data = 0,nrow = nrow(l_r_inter), ncol = length(cell_type)) ## A->A,A->B,A->C,,,,C->C
  expr_r_regulons <- as.data.frame(expr_r_regulons)
  rownames(expr_r_regulons) <- paste(l_r_inter$Ligand_Symbol, l_r_inter$Receptor_Symbol,sep = "-")
  colnames(expr_r_regulons) <- cell_type

  for (n in 1:nrow(l_r_inter)) {
    sender_tmp <- l_r_inter[n,1]
    receiver_tmp <- l_r_inter[n,2]
    row_index <- paste(sender_tmp, receiver_tmp,sep = "-")
    # print(n)

    val_tmp = 0
    if( sum(l_r_inter[n,] %in% detect_gene)==2 ){

      info_tmp <- dplyr::filter(triple_relation, Ligand_Symbol==sender_tmp & Receptor_Symbol==receiver_tmp)[,5:7]
      tfs_tmp <- info_tmp$TF_Symbol[info_tmp$TF_Symbol %in% detect_gene]
      if(length(tfs_tmp) > 0){
        regulon_tmp_df <- regulons_matrix[tfs_tmp,]
        if(method=='max'){
          expr_r_regulons[row_index,] = as.numeric(apply(regulon_tmp_df, 2, function(x){max(x)}))
        }else if(method=="weighted"){
          distance2w_tmp <- (1/DistanceKEGG[row_index,tfs_tmp])
          w_tmp<- distance2w_tmp/sum(distance2w_tmp)
          expr_r_regulons[row_index,] = as.numeric(apply(regulon_tmp_df, 2, function(x){
            sum(w_tmp*x)
          }))
        }else if(method=="mean"){
          expr_r_regulons[row_index,] = as.numeric(apply(regulon_tmp_df, 2, function(x){mean(x)}))
        }
      }
    }
  }

  print("step5: softmax for ligand")
  # softmax for ligand
  ligand_symbol <- unique(triple_relation$Ligand_Symbol)
  softmax_ligand <- expr_mean[intersect(ligand_symbol, detect_gene),]
  colnames(softmax_ligand) <- colnames(expr_mean)
  rowCounts <- rowSums(softmax_ligand)

  softmax_ligand <- do.call(rbind,lapply(1:nrow(softmax_ligand), function(i){
    softmax_ligand[i,]/rowCounts[i]
  }))

  # softmax for receptor
  receptor_symbol <- unique(triple_relation$Receptor_Symbol)
  softmax_receptor <- expr_mean[intersect(receptor_symbol, detect_gene),]
  colnames(softmax_receptor) <- colnames(expr_mean)
  rowCounts <- rowSums(softmax_receptor)

  softmax_receptor <- do.call(rbind,lapply(1:nrow(softmax_receptor), function(i){
    softmax_receptor[i,]/rowCounts[i]
  }))

  #  l-r in cell type level
  print("step6: score ligand-receptor relation (weighted, max, or mean) ####")

  l_r_inter <- unique(triple_relation[,5:6])
  expr_l_r <- matrix(data = 0,nrow = nrow(l_r_inter), ncol = length(cell_type)^2) ##A->A,A->B,A->C,,,,C->C
  expr_l_r <- as.data.frame(expr_l_r)
  rownames(expr_l_r) <- paste(l_r_inter$Ligand_Symbol, l_r_inter$Receptor_Symbol,sep = "-")
  myColnames <- character()
  for (i in cell_type) {
    for (j in cell_type) {
      myColnames <- c(myColnames, paste(i,j,sep = "-"))
    }
  }
  colnames(expr_l_r) <- myColnames

  for (n in 1:nrow(l_r_inter)) {
    sender_tmp <- l_r_inter[n,1]
    receiver_tmp <- l_r_inter[n,2]
    row_index <- paste(sender_tmp, receiver_tmp,sep = "-")
    # print(n)
    for (i in cell_type) {
      for (j in cell_type) {
        myColnames <- c(myColnames, paste(i,j,sep = "-"))
        val_tmp = 0
        if( sum(l_r_inter[n,] %in% detect_gene)==2 ){
          sender_val <- expr_mean[sender_tmp,i]
          receiver_val <- expr_mean[receiver_tmp,j]
          tf_val <- expr_r_regulons[row_index,j]

          if(tf_val > 0 & sender_val>0 & receiver_val >0){
            sender_val_weighted <- softmax_ligand[sender_tmp, i]
            receiver_val_weighted <- softmax_receptor[receiver_tmp, j]
            val_tmp <- 100*(sender_val_weighted^2 + receiver_val_weighted^2) * tf_val
          }else{
            val_tmp = 0
          }
        }else{
          val_tmp = 0
        }
        col_index_tmp <- paste(i,j,sep = "-")
        expr_l_r[n,col_index_tmp] <- val_tmp
      }
    }
  }

  expr_l_r <- expr_l_r[apply(expr_l_r, 1, function(x){sum(x!=0)})>0,]
  expr_l_r <- as.data.frame(expr_l_r)

  expr_l_r_log2 <- log2(expr_l_r+1)
  expr_l_r_log2_scale <- (expr_l_r_log2-min(expr_l_r_log2))/(max(expr_l_r_log2)-min(expr_l_r_log2))


  Result <- list(expr_mean = expr_mean,
                 regulons_matrix = regulons_matrix,
                 gsea.list = gsea.list,
                 fc.list = fc.list,
                 expr_r_regulons = expr_r_regulons,
                 softmax_ligand = softmax_ligand,
                 softmax_receptor = softmax_receptor,
                 expr_l_r =  expr_l_r,
                 expr_l_r_log2 = expr_l_r_log2,
                 expr_l_r_log2_scale = expr_l_r_log2_scale,
                 DistanceKEGG= DistanceKEGG)

  return(Result)
}










