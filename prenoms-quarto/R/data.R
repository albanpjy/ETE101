# Connexion DuckDB en mémoire sur les Parquet de data/ et tables dérivées.
# Ce sont les jumelles des requêtes Evidence (prenoms-dashboard/sources/prenoms/*.sql).

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
})

DATA_DIR <- if (dir.exists("data")) "data" else file.path("..", "data")
pq <- function(f) sprintf("read_parquet('%s')", normalizePath(file.path(DATA_DIR, f), winslash = "/"))

con <- dbConnect(duckdb(shared_home = FALSE))
run <- function(sql) invisible(dbExecute(con, sql))

# Exécute une requête paramétrée (`?`) et renvoie un data.frame
q <- function(sql, ...) {
  params <- list(...)
  if (length(params)) dbGetQuery(con, sql, params = unname(params)) else dbGetQuery(con, sql)
}

run(sprintf("create table meta as select * from %s", pq("meta.parquet")))

# Niveau le plus fin : sexe × prénom × année × département
run(sprintf("
  create table detail as
  select sexe, prenom, libelle, annee::integer as annee, dpt, nombre::integer as nombre
  from %s
  where annee is not null and dpt is not null and prenom <> '_PRENOMS_RARES'", pq("prenoms_departements.parquet")))

# Fichier national (prénoms rares inclus pour les totaux)
run(sprintf("
  create table france as
  select sexe, prenom, libelle, annee::integer as annee, nombre::integer as nombre,
         prenom = '_PRENOMS_RARES' as est_rare
  from %s
  where annee is not null", pq("prenoms_france.parquet")))

run("
  create table naissances as
  select annee, sexe, sum(nombre)::bigint as naissances,
         count(distinct prenom) filter (where not est_rare) as prenoms_distincts
  from france group by all order by annee, sexe")

run(sprintf("
  create table naissances_dpt as
  select dpt, annee::integer as annee, sexe, sum(nombre)::bigint as naissances
  from %s
  where annee is not null and dpt is not null
  group by all", pq("prenoms_departements.parquet")))

run("
  create table rangs as
  with tot as (select annee, sexe, sum(nombre) as total from france group by all)
  select f.sexe, f.prenom, f.libelle, f.annee, f.nombre,
         (rank() over (partition by f.sexe, f.annee order by f.nombre desc))::integer as rang,
         1000.0 * f.nombre / t.total as pour_mille
  from france f join tot t using (annee, sexe)
  where not f.est_rare")

run("
  create table catalogue as
  with p as (
    select prenom, libelle, annee, sum(nombre) as n,
           sum(nombre) filter (where sexe = 'F') as nf,
           sum(nombre) filter (where sexe = 'M') as nm
    from france where not est_rare group by all
  )
  select prenom, libelle,
         sum(n)::bigint as total,
         coalesce(sum(nf), 0)::bigint as total_f,
         coalesce(sum(nm), 0)::bigint as total_m,
         coalesce(sum(nf), 0) / sum(n) as part_f,
         case when coalesce(sum(nf), 0) / sum(n) >= 0.9 then 'F' || chr(233) || 'minin'
              when coalesce(sum(nf), 0) / sum(n) <= 0.1 then 'Masculin'
              else 'Mixte' end as genre,
         arg_max(annee, n)::integer as annee_pic,
         max(n)::bigint as naissances_pic,
         min(annee)::integer as premiere_annee,
         max(annee)::integer as derniere_annee
  from p group by prenom, libelle
  order by total desc")

run(sprintf("
  create table departements as
  select code as dpt, nom, region, code || ' ' || chr(183) || ' ' || nom as libelle_dpt
  from %s
  where code in (select distinct dpt from detail)
  order by code", pq("departements.parquet")))

META <- q("select * from meta")
ANNEE_MIN <- META$annee_min
ANNEE_MAX <- META$annee_max

# Référentiel complet (noms des départements pour la carte, y compris 2A/2B)
DEPTS <- utils::read.csv(file.path(DATA_DIR, "departements.csv"), colClasses = "character", encoding = "UTF-8")
names(DEPTS)[names(DEPTS) == "code"] <- "dpt"
