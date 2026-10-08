-- Niveau le plus fin : sexe × prénom × année × département
select sexe, prenom, libelle, annee::integer as annee, dpt, nombre::integer as nombre
from v_departements_detail
where annee is not null and dpt is not null and prenom <> '_PRENOMS_RARES'
