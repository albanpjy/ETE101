-- Total des naissances par département, année et sexe (prénoms rares inclus)
select dpt, annee::integer as annee, sexe, sum(nombre)::bigint as naissances
from v_departements_detail
where annee is not null and dpt is not null
group by all
