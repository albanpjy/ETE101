# Convertit le fond de carte SVG des départements (svg-maps, CC-BY-4.0) en polygones
# utilisables par plotly : data/departements_contours.csv (dpt, anneau, x, y).
#
# Usage : Rscript R/contours.R chemin/vers/france.departments.svg
# (fichier fourni par le paquet npm @svg-maps/france.departments)
# Le CSV produit est versionné : ce script ne sert qu'à le régénérer.

args <- commandArgs(trailingOnly = TRUE)
svg <- paste(readLines(args[1], warn = FALSE, encoding = "UTF-8"), collapse = "\n")

paths <- regmatches(svg, gregexpr("<path[^>]*>", svg))[[1]]
attr_of <- function(tag, name) sub(sprintf('.*\\s%s="([^"]*)".*', name), "\\1", tag)

parse_path <- function(d) {
  # seules les commandes « m » (relative, lignes implicites) et « z » sont utilisées
  tokens <- regmatches(d, gregexpr("[mMzZ]|-?[0-9.]+(e-?[0-9]+)?", d))[[1]]
  rings <- list(); cur <- NULL; pos <- c(0, 0); start <- c(0, 0); i <- 1; ring <- 0
  while (i <= length(tokens)) {
    t <- tokens[i]
    if (t %in% c("z", "Z")) {
      if (!is.null(cur)) rings[[length(rings) + 1]] <- cur
      cur <- NULL; pos <- start; i <- i + 1
    } else if (t %in% c("m", "M")) {
      i <- i + 1; first <- TRUE
      while (i + 1 <= length(tokens) && !grepl("[a-zA-Z]", tokens[i])) {
        xy <- as.numeric(tokens[i:(i + 1)])
        pos <- if (t == "m" || !first) pos + xy else xy
        if (first) { start <- pos; ring <- ring + 1; cur <- data.frame(anneau = ring, x = pos[1], y = pos[2]) }
        else cur <- rbind(cur, data.frame(anneau = ring, x = pos[1], y = pos[2]))
        first <- FALSE; i <- i + 2
      }
    } else i <- i + 1
  }
  if (!is.null(cur)) rings[[length(rings) + 1]] <- cur
  do.call(rbind, rings)
}

out <- do.call(rbind, lapply(paths, function(p) {
  cbind(dpt = attr_of(p, "id"), parse_path(attr_of(p, "d")))
}))
out$x <- round(out$x, 2); out$y <- round(out$y, 2)
write.csv(out, "data/departements_contours.csv", row.names = FALSE)
cat(length(unique(out$dpt)), "départements,", nrow(out), "points\n")
