# Ingestion du « Fichier des prénoms » de l'INSEE (data.gouv.fr) vers Parquet, avec DuckDB.
#
# Usage :
#   Rscript R/ingest.R                                   # découverte automatique sur data.gouv.fr
#   Rscript R/ingest.R --dpt-file dpt2022_csv.zip [--nat-file nat2022_csv.zip]
#   Rscript R/ingest.R --dpt-url URL [--nat-url URL]
#
# Produit dans data/ : prenoms_departements.parquet, prenoms_france.parquet,
#                      departements.parquet, meta.parquet

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(jsonlite)
})

API <- "https://www.data.gouv.fr/api/1"
DATASET_SLUGS <- c("fichier-des-prenoms-depuis-1900", "fichier-des-prenoms-1900-2023", "fichier-des-prenoms-1900-2022")

# Noms de colonnes rencontrés selon les éditions INSEE
COLS <- list(
  sexe   = c("sexe", "sex", "genre"),
  prenom = c("preusuel", "prenom", "prénom", "prenom_usuel"),
  annee  = c("annais", "annee", "année", "periode", "période", "annee_naissance", "time_period"),
  dpt    = c("dpt", "departement", "département", "dep", "code_departement", "geo", "geo_object", "geo_code"),
  nombre = c("nombre", "valeur", "effectif", "nb", "obs_value", "nombre_naissances"),
  niveau = c("niveau_geographique", "geo_level", "niveau")
)

# --------------------------------------------------------------------------- arguments
parse_args <- function(a) {
  out <- list()
  i <- 1
  while (i <= length(a)) {
    if (startsWith(a[i], "--")) { out[[sub("^--", "", a[i])]] <- a[i + 1]; i <- i + 2 } else i <- i + 1
  }
  out
}
args <- parse_args(commandArgs(trailingOnly = TRUE))

root <- normalizePath(".")
data_dir <- file.path(root, "data")
raw_dir <- file.path(data_dir, "raw")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

# --------------------------------------------------------------------------- découverte
find_dataset <- function() {
  for (slug in DATASET_SLUGS) {
    ds <- tryCatch(fromJSON(sprintf("%s/datasets/%s/", API, slug), simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(ds)) return(ds)
  }
  res <- fromJSON(sprintf("%s/datasets/?q=%s&page_size=10", API, URLencode("fichier des prénoms depuis 1900")), simplifyVector = FALSE)
  for (d in res$data) if (grepl("insee|institut national", tolower(d$organization$name %||% ""))) return(d)
  stop("Jeu de données INSEE « Fichier des prénoms » introuvable sur data.gouv.fr")
}
`%||%` <- function(a, b) if (is.null(a)) b else a

classify <- function(r) {
  txt <- tolower(paste(r$title %||% "", r$url %||% ""))
  if (grepl("dpt|d[ée]part", txt)) return("dpt")
  if (grepl("nat|national|france", txt)) return("nat")
  NA_character_
}

pick_resources <- function(ds) {
  best <- list()
  for (r in ds$resources) {
    k <- classify(r)
    if (is.na(k)) next
    stamp <- r$last_modified %||% r$created_at %||% ""
    if (is.null(best[[k]]) || stamp > best[[k]]$stamp) best[[k]] <- list(url = r$url, title = r$title, stamp = stamp)
  }
  best
}

download <- function(url) {
  dest <- file.path(raw_dir, basename(sub("\\?.*$", "", url)))
  if (file.exists(dest) && file.size(dest) > 0) { message("  ↺ déjà téléchargé : ", basename(dest)); return(dest) }
  message("  ↓ ", url)
  options(timeout = max(600, getOption("timeout")))
  utils::download.file(url, dest, mode = "wb", quiet = TRUE)
  dest
}

unpack <- function(path) {
  if (!grepl("\\.zip$", path, ignore.case = TRUE)) return(path)
  files <- utils::unzip(path, list = TRUE)
  files <- files[grepl("\\.(csv|parquet|txt)$", files$Name, ignore.case = TRUE) & !grepl("^__MACOSX", files$Name), ]
  member <- files$Name[which.max(files$Length)]
  out <- file.path(raw_dir, sub("\\.zip$", "_unzip", basename(path)))
  target <- file.path(out, basename(member))
  if (!file.exists(target)) utils::unzip(path, files = member, exdir = out, junkpaths = TRUE)
  target
}

# --------------------------------------------------------------------------- normalisation
run <- function(...) invisible(DBI::dbExecute(...))
q <- function(x) paste0('"', gsub('"', '""', x), '"')

read_raw <- function(con, path, view) {
  p <- gsub("'", "''", normalizePath(path))
  src <- if (grepl("\\.parquet$", p)) sprintf("read_parquet('%s')", p) else
    sprintf("read_csv('%s', all_varchar = true, header = true, auto_detect = true, sample_size = -1)", p)
  run(con, sprintf("create or replace view %s as select * from %s", view, src))
}

normalize <- function(con, view, out, with_dpt) {
  cols <- dbGetQuery(con, sprintf("describe %s", view))$column_name
  m <- lapply(COLS, function(c) { hit <- cols[tolower(trimws(cols)) %in% c]; if (length(hit)) hit[1] else NA })
  needed <- c("sexe", "prenom", "annee", "nombre", if (with_dpt) "dpt")
  if (any(is.na(unlist(m[needed])))) stop("Colonnes introuvables dans : ", paste(cols, collapse = ", "))
  message("  colonnes détectées : ", paste(names(m)[!is.na(m)], unlist(m[!is.na(m)]), sep = "=", collapse = ", "))

  where <- ""
  if (!is.na(m$niveau)) where <- if (with_dpt) sprintf("where lower(cast(%s as varchar)) like '%%dep%%'", q(m$niveau)) else
    sprintf("where lower(cast(%s as varchar)) similar to '.*(fr|nat|pays).*'", q(m$niveau))

  dpt_expr <- ""
  if (with_dpt) {
    raw <- sprintf("upper(trim(cast(%s as varchar)))", q(m$dpt))
    dpt_expr <- sprintf(", case
        when regexp_matches(%1$s, '(2A|2B)$') then regexp_extract(%1$s, '(2A|2B)$')
        when regexp_matches(%1$s, '97[0-9]$') then regexp_extract(%1$s, '(97[0-9])$')
        when regexp_matches(%1$s, '[0-9]{1,2}$') then lpad(regexp_extract(%1$s, '([0-9]{1,2})$'), 2, '0')
        else null end as dpt", raw)
  }

  run(con, sprintf("
    create or replace table %s as
    with src as (
      select
        case upper(trim(cast(%s as varchar)))
          when '1' then 'M' when 'M' then 'M' when 'H' then 'M' when 'G' then 'M' when 'MASCULIN' then 'M'
          when '2' then 'F' when 'F' then 'F' when 'FEMININ' then 'F' when 'F' || chr(201) || 'MININ' then 'F'
        end as sexe,
        upper(trim(cast(%s as varchar))) as prenom,
        try_cast(regexp_extract(cast(%s as varchar), '([12][0-9]{3})') as smallint) as annee,
        try_cast(replace(cast(%s as varchar), ' ', '') as integer) as nombre
        %s
      from %s %s
    )
    select sexe, prenom, annee, %s sum(nombre)::integer as nombre
    from src
    where sexe is not null and prenom is not null and prenom <> '' and nombre > 0
    group by all",
    out, q(m$sexe), q(m$prenom), q(m$annee), q(m$nombre), dpt_expr, view, where, if (with_dpt) "dpt," else ""))
  n <- dbGetQuery(con, sprintf("select count(*) n, sum(nombre) s from %s", out))
  message(sprintf("  → %s : %s lignes, %s naissances", out, format(n$n, big.mark = " "), format(n$s, big.mark = " ")))
}

# « JEAN-PIERRE » → « Jean-Pierre », « N'GOLO » → « N'Golo »
# Calculé dans DuckDB : Unicode correct (accents) quelle que soit la locale de R.
LIBELLE_SQL <- r"(
create or replace macro cap(s, sep) as
  array_to_string(list_transform(string_split(s, sep), w -> upper(w[1]) || w[2:]), sep);
create or replace macro libelle(p) as
  case when starts_with(p, '_') then 'Pr' || chr(233) || 'noms rares'
       else cap(cap(cap(lower(p), '-'), ''''), ' ') end;
)"

# --------------------------------------------------------------------------- main
meta <- list(source = "INSEE \u2014 Fichier des pr\u00e9noms (data.gouv.fr)", edition = NA_character_,
             url_dpt = NA_character_, url_nat = NA_character_, demo = FALSE,
             genere_le = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))

message("1/4  Localisation des fichiers")
dpt_path <- args[["dpt-file"]]
nat_path <- args[["nat-file"]]
if (is.null(dpt_path)) {
  dpt_url <- args[["dpt-url"]]
  nat_url <- args[["nat-url"]]
  if (is.null(dpt_url)) {
    ds <- find_dataset()
    message("  jeu de données : ", ds$title)
    res <- pick_resources(ds)
    if (is.null(res$dpt)) stop("Ressource départementale introuvable : utilisez --dpt-url")
    dpt_url <- res$dpt$url
    nat_url <- nat_url %||% res$nat$url
    meta$edition <- res$dpt$title
  }
  meta$url_dpt <- dpt_url
  meta$url_nat <- nat_url %||% NA_character_
  message("2/4  Téléchargement")
  dpt_path <- download(dpt_url)
  if (!is.null(nat_url)) nat_path <- download(nat_url)
} else {
  meta$edition <- basename(dpt_path)
}

con <- dbConnect(duckdb(shared_home = FALSE))
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

message("3/4  Normalisation (DuckDB)")
read_raw(con, unpack(dpt_path), "raw_dpt")
normalize(con, "raw_dpt", "dpt", with_dpt = TRUE)
if (!is.null(nat_path)) {
  read_raw(con, unpack(nat_path), "raw_nat")
  normalize(con, "raw_nat", "nat", with_dpt = FALSE)
} else {
  message("  pas de fichier national : agrégation du fichier départemental")
  run(con, "create table nat as select sexe, prenom, annee, sum(nombre)::integer as nombre from dpt group by all")
}

run(con, LIBELLE_SQL)
run(con, "create table labels as select prenom, libelle(prenom) as libelle
          from (select distinct prenom from nat union select distinct prenom from dpt)")
run(con, sprintf("create table departements as select * from read_csv('%s', all_varchar = true)",
                       file.path(data_dir, "departements.csv")))

message("4/4  Écriture Parquet")
exports <- c(
  prenoms_departements = "select d.sexe, d.prenom, l.libelle, d.annee, d.dpt, d.nombre from dpt d join labels l using (prenom) order by d.prenom, d.annee, d.dpt",
  prenoms_france = "select n.sexe, n.prenom, l.libelle, n.annee, n.nombre from nat n join labels l using (prenom) order by n.prenom, n.annee",
  departements = "select * from departements"
)
for (nm in names(exports)) {
  target <- file.path(data_dir, paste0(nm, ".parquet"))
  run(con, sprintf("copy (%s) to '%s' (format parquet, compression zstd, row_group_size 250000)", exports[[nm]], target))
  message(sprintf("  ✓ data/%s.parquet (%.1f Mo)", nm, file.size(target) / 1e6))
}
yr <- dbGetQuery(con, "select min(annee) as annee_min, max(annee) as annee_max from nat")
meta_df <- as.data.frame(c(meta, yr), stringsAsFactors = FALSE)
dbWriteTable(con, "meta", meta_df, overwrite = TRUE)
run(con, sprintf("copy (select source, edition, url_dpt, url_nat, demo, genere_le, annee_min::int as annee_min, annee_max::int as annee_max from meta) to '%s' (format parquet)", file.path(data_dir, "meta.parquet")))
message("Terminé. Lancez maintenant : quarto preview prenoms.qmd")
