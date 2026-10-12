# Palette, formats français et graphiques plotly partagés par le tableau de bord.

suppressPackageStartupMessages({
  library(plotly)
  library(DT)
})

# Palette catégorielle validée (même ordre que le tableau de bord Evidence)
PAL <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948")
COUL_SEXE <- c("Filles" = "#eb6834", "Garçons" = "#2a78d6")
# Rampe séquentielle bleue, du clair au foncé (7 marches)
RAMPE <- c("#dbe9fa", "#b5d2f4", "#86b5ec", "#5596e2", "#2a78d6", "#1d5dab", "#13427c")
GRIS_VIDE <- "#e9e8e4"
GRIS_AUTRES <- "#b9b8b2"
ENCRE <- "#52514e"

lib_sexe <- function(s) ifelse(s == "F", "Filles", "Garçons")

# ------------------------------------------------------------------ formats
fnum <- function(x, d = 0) formatC(x, format = "f", digits = d, big.mark = " ", decimal.mark = ",")
fpct <- function(x, d = 1) paste0(fnum(100 * x, d), " %")
fpm  <- function(x, d = 2) paste0(fnum(x, d), " ‰")

# ------------------------------------------------------------------ plotly
# Mise en forme commune : fond transparent, grille discrète, séparateurs français
style_plotly <- function(p, x_titre = NULL, y_titre = NULL, legende = TRUE) {
  p |>
    layout(
      separators = ", ",
      paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      font = list(family = "Inter, system-ui, sans-serif", color = ENCRE, size = 12),
      xaxis = list(title = x_titre %||% "", showgrid = FALSE, zeroline = FALSE, linecolor = "#d6d5d0"),
      yaxis = list(title = y_titre %||% "", gridcolor = "#ecebe7", zeroline = FALSE),
      legend = list(orientation = "h", x = 0, y = 1.08, bgcolor = "rgba(0,0,0,0)"),
      showlegend = legende,
      hovermode = "x unified",
      margin = list(l = 10, r = 10, t = 30, b = 10)
    ) |>
    config(displaylogo = FALSE, locale = "fr",
           modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d"))
}

# Courbes ou aires par sexe sur l'axe des années
serie_sexe <- function(df, y, type = c("line", "area", "bar"), y_titre = NULL, fmt_y = ",d") {
  type <- match.arg(type)
  df$sexe_lib <- factor(lib_sexe(df$sexe), levels = c("Filles", "Garçons"))
  p <- plot_ly(df, x = ~annee, y = df[[y]], color = ~sexe_lib, colors = COUL_SEXE)
  p <- switch(type,
    line = add_lines(p, line = list(width = 2)),
    area = add_trace(p, type = "scatter", mode = "lines", stackgroup = "un", line = list(width = 1)),
    bar  = add_bars(p) |> layout(barmode = "stack", bargap = 0.15)
  )
  style_plotly(p, y_titre = y_titre) |> layout(yaxis = list(tickformat = fmt_y))
}

# Barres horizontales triées (classement)
barres_h <- function(df, x, y, couleur = PAL[1], fmt_x = ".1f", titre_x = NULL) {
  df[[y]] <- factor(df[[y]], levels = rev(df[[y]]))
  plot_ly(df, x = df[[x]], y = df[[y]], type = "bar", orientation = "h",
          marker = list(color = couleur),
          hovertemplate = paste0("%{y} : %{x:", fmt_x, "}<extra></extra>")) |>
    style_plotly(x_titre = titre_x, legende = FALSE) |>
    layout(hovermode = "closest", yaxis = list(gridcolor = "rgba(0,0,0,0)", title = ""),
           xaxis = list(tickformat = fmt_x, showgrid = TRUE, gridcolor = "#ecebe7"))
}

# ------------------------------------------------------------------ tableaux
DT_FR <- list(
  search = "Rechercher :", lengthMenu = "_MENU_ lignes", info = "_START_ à _END_ sur _TOTAL_",
  infoEmpty = "Aucune ligne", zeroRecords = "Aucun résultat", infoFiltered = "(filtré de _MAX_)",
  paginate = list(previous = "‹", `next` = "›", first = "«", last = "»")
)

tableau <- function(df, pageLength = 10, recherche = FALSE, ...) {
  datatable(df, rownames = FALSE, class = "compact hover", escape = TRUE, ...,
            options = list(pageLength = pageLength, dom = if (recherche) "ftp" else "tp",
                           language = DT_FR, ordering = TRUE, autoWidth = FALSE))
}

# ------------------------------------------------------------------ carte
CONTOURS <- read.csv(file.path(DATA_DIR, "departements_contours.csv"), colClasses = c(dpt = "character"),
                     encoding = "UTF-8")
CONTOURS$y <- -CONTOURS$y
DROM <- data.frame(dpt = c("971", "972", "973", "974", "976"),
                   nom = c("Guadeloupe", "Martinique", "Guyane", "La Réunion", "Mayotte"))
DROM$x0 <- 20 + (seq_len(nrow(DROM)) - 1) * 60
DROM$y0 <- -626

# Géométrie : un polygone (anneaux séparés par NA) et un point d'ancrage par département
GEOM <- local({
  metro <- lapply(split(CONTOURS, CONTOURS$dpt), function(d) {
    rings <- split(d, d$anneau)
    big <- rings[[which.max(sapply(rings, nrow))]]
    xs <- unlist(lapply(rings, function(r) c(r$x, r$x[1], NA)))
    ys <- unlist(lapply(rings, function(r) c(r$y, r$y[1], NA)))
    list(dpt = d$dpt[1], x = xs, y = ys, cx = mean(big$x), cy = mean(big$y))
  })
  drom <- lapply(seq_len(nrow(DROM)), function(i) {
    r <- DROM[i, ]
    list(dpt = r$dpt, x = c(r$x0, r$x0 + 44, r$x0 + 44, r$x0, r$x0),
         y = c(r$y0, r$y0, r$y0 + 34, r$y0 + 34, r$y0), cx = r$x0 + 22, cy = r$y0 + 17)
  })
  setNames(c(metro, drom), c(names(metro), DROM$dpt))
})

#' Carte choroplèthe des départements
#' @param df       data.frame avec une colonne `dpt`
#' @param valeur   colonne numérique (mode « sequentiel ») ou affichée dans l'infobulle
#' @param categorie colonne catégorielle (mode « categoriel ») : 5 catégories max, le reste en gris
#' @param surbrillance code du département à entourer (mode « situation » : seul lui est coloré)
#' @param fmt      fonction de formatage de `valeur`
#' @param info     fonction(ligne) -> texte supplémentaire de l'infobulle
carte_france <- function(df, valeur = NULL, categorie = NULL, mode = NULL, surbrillance = NULL,
                         fmt = fnum, titre_legende = "", info = NULL, nom = "nom") {
  mode <- mode %||% (if (!is.null(categorie)) "categoriel" else "sequentiel")
  df <- as.data.frame(df)
  df$dpt <- as.character(df$dpt)
  # Corse codée « 20 » selon les éditions : on la reporte sur 2A et 2B
  if ("20" %in% df$dpt) for (c in c("2A", "2B")) if (!c %in% df$dpt) df <- rbind(df, transform(df[df$dpt == "20", ], dpt = c))
  lignes <- split(df, df$dpt)

  hl <- function(id) !is.null(surbrillance) && (id == surbrillance || (surbrillance == "20" && id %in% c("2A", "2B")))

  couleurs <- setNames(rep(GRIS_VIDE, length(GEOM)), names(GEOM))
  legende <- NULL
  if (mode == "sequentiel" && nrow(df)) {
    v <- df[[valeur]]
    br <- unique(stats::quantile(v, probs = seq(0, 1, length.out = 8), na.rm = TRUE, names = FALSE))
    classe <- if (length(br) > 1) as.integer(cut(v, br, include.lowest = TRUE)) else rep(4L, length(v))
    pas <- if (length(br) > 2) round((classe - 1) / (length(br) - 2) * 6) + 1 else 4
    couleurs[df$dpt] <- RAMPE[pas]
    legende <- list(min = min(v, na.rm = TRUE), max = max(v, na.rm = TRUE))
  } else if (mode == "categoriel" && nrow(df)) {
    freq <- sort(table(df[[categorie]][!df$dpt %in% c("2A", "2B")]), decreasing = TRUE)
    tops <- head(names(freq), 5)
    couleurs[df$dpt] <- ifelse(df[[categorie]] %in% tops, PAL[match(df[[categorie]], tops)], GRIS_AUTRES)
    legende <- list(cats = tops, n = as.integer(freq[tops]), autres = length(freq) > length(tops))
  } else if (mode == "situation") {
    for (id in names(GEOM)) if (hl(id)) couleurs[id] <- PAL[1]
  }

  # Un tracé par couleur (plotly remplit séparément chaque segment délimité par NA) : rapide
  p <- plot_ly()
  for (col in unique(couleurs)) {
    ids <- names(couleurs)[couleurs == col]
    p <- add_trace(p, type = "scatter", mode = "lines", fill = "toself", fillcolor = col,
                   x = unlist(lapply(GEOM[ids], function(g) c(g$x, NA))),
                   y = unlist(lapply(GEOM[ids], function(g) c(g$y, NA))),
                   line = list(color = "#ffffff", width = 0.7), hoverinfo = "none", showlegend = FALSE)
  }
  surb <- Filter(hl, names(GEOM))
  if (length(surb)) p <- add_trace(p, type = "scatter", mode = "lines",
                                   x = unlist(lapply(GEOM[surb], function(g) c(g$x, NA))),
                                   y = unlist(lapply(GEOM[surb], function(g) c(g$y, NA))),
                                   line = list(color = "#0b0b0b", width = 2.4), hoverinfo = "none", showlegend = FALSE)

  # Infobulles : un point invisible au centre de chaque département
  ids <- names(GEOM)
  noms <- vapply(ids, function(id) {
    r <- lignes[[id]]
    if (!is.null(r) && nom %in% names(r)) as.character(r[[nom]][1]) else
      DEPTS$nom[match(id, DEPTS$dpt)] %||% id
  }, "")
  txt <- vapply(ids, function(id) {
    r <- lignes[[id]]
    entete <- sprintf("<b>%s</b> (%s)", noms[[id]], id)
    if (mode == "situation") return(entete)
    if (is.null(r)) return(paste0(entete, "<br>Aucune donnée"))
    corps <- if (mode == "categoriel") sprintf("%s<br>%s %s", r[[categorie]][1], titre_legende, fmt(r[[valeur]][1])) else
      sprintf("%s <b>%s</b>", titre_legende, fmt(r[[valeur]][1]))
    extra <- if (!is.null(info)) paste0("<br>", info(r[1, ])) else ""
    paste0(entete, "<br>", corps, extra)
  }, "")
  p <- add_trace(p, type = "scatter", mode = "markers",
                 x = vapply(GEOM, `[[`, 0, "cx"), y = vapply(GEOM, `[[`, 0, "cy"),
                 marker = list(size = 18, opacity = 0), text = txt, hoverinfo = "text", showlegend = FALSE,
                 hoverlabel = list(bgcolor = "#ffffff", bordercolor = "#d6d5d0", font = list(color = "#0b0b0b")))
  p <- add_annotations(p, x = DROM$x0 + 22, y = DROM$y0 - 10, text = DROM$dpt, showarrow = FALSE,
                       font = list(size = 10, color = "#8a8984"))

  # Légende
  if (!is.null(legende$cats)) {
    for (i in seq_along(legende$cats)) {
      p <- add_trace(p, type = "scatter", mode = "markers", x = -9999, y = -9999,
                     name = sprintf("%s (%d)", legende$cats[i], legende$n[i]),
                     marker = list(color = PAL[i], size = 11, symbol = "square"), showlegend = TRUE)
    }
    if (legende$autres) p <- add_trace(p, type = "scatter", mode = "markers", x = -9999, y = -9999,
                                       name = "Autres", marker = list(color = GRIS_AUTRES, size = 11, symbol = "square"))
  } else if (!is.null(legende$min)) {
    p <- add_annotations(p, x = 20, y = -652, xanchor = "left", showarrow = FALSE,
                         text = sprintf("%s  %s  <span style='color:%s'>■■</span><span style='color:%s'>■■</span><span style='color:%s'>■■</span><span style='color:%s'>■■</span>  %s",
                                        titre_legende, fmt(legende$min), RAMPE[2], RAMPE[4], RAMPE[6], RAMPE[7], fmt(legende$max)),
                         font = list(size = 11, color = ENCRE))
  }

  p |>
    layout(
      xaxis = list(visible = FALSE, range = c(0, 613), fixedrange = TRUE),
      yaxis = list(visible = FALSE, range = c(-664, 0), scaleanchor = "x", fixedrange = TRUE),
      paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      margin = list(l = 0, r = 0, t = 0, b = 0),
      legend = list(orientation = "h", x = 0, y = 0, yanchor = "top", font = list(size = 11, color = ENCRE)),
      hovermode = "closest", dragmode = FALSE
    ) |>
    config(displayModeBar = FALSE)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a
