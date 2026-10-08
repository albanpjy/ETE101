-- Total des naissances recensées par année et sexe (France)
select annee::integer as annee, sexe, sum(nombre)::bigint as naissances,
       count(distinct prenom) filter (where prenom <> '_PRENOMS_RARES') as prenoms_distincts
from v_france
where annee is not null
group by all
order by annee, sexe
