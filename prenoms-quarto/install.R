# Installe les paquets R nécessaires au tableau de bord.
# Usage : Rscript install.R   (ou source("install.R") dans RStudio)
paquets <- c("shiny", "bslib", "DBI", "duckdb", "plotly", "DT", "htmltools", "jsonlite", "rmarkdown", "knitr")
manquants <- setdiff(paquets, rownames(installed.packages()))
if (length(manquants)) install.packages(manquants, repos = "https://cloud.r-project.org")
cat("Paquets prêts :", paste(paquets, collapse = ", "), "\n")
