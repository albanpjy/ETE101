-- Rang national de chaque prénom, par année et sexe, et part pour 1 000 naissances
with tot as (
  select annee, sexe, sum(nombre) as total from v_france where annee is not null group by all
)
select f.sexe, f.prenom, f.libelle, f.annee::integer as annee, f.nombre::integer as nombre,
       (rank() over (partition by f.sexe, f.annee order by f.nombre desc))::integer as rang,
       1000.0 * f.nombre / t.total as pour_mille
from v_france f join tot t using (annee, sexe)
where f.annee is not null and f.prenom <> '_PRENOMS_RARES'
