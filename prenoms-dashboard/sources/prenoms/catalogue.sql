-- Une ligne par prénom (tous sexes) : utile pour la recherche et les palmarès
with p as (
  select prenom, libelle, annee, sum(nombre) as n,
         sum(nombre) filter (where sexe = 'F') as nf,
         sum(nombre) filter (where sexe = 'M') as nm
  from v_france
  where annee is not null and prenom <> '_PRENOMS_RARES'
  group by all
)
select prenom, libelle,
       sum(n)::bigint as total,
       coalesce(sum(nf), 0)::bigint as total_f,
       coalesce(sum(nm), 0)::bigint as total_m,
       coalesce(sum(nf), 0) / sum(n) as part_f,
       case when coalesce(sum(nf), 0) / sum(n) >= 0.9 then 'Féminin'
            when coalesce(sum(nf), 0) / sum(n) <= 0.1 then 'Masculin'
            else 'Mixte' end as genre,
       arg_max(annee, n)::integer as annee_pic,
       max(n)::bigint as naissances_pic,
       min(annee)::integer as premiere_annee,
       max(annee)::integer as derniere_annee,
       libelle || ' (' || replace(format('{:,}', sum(n)::bigint), ',', ' ') || ')' as libelle_recherche
from p
group by prenom, libelle
order by total desc
