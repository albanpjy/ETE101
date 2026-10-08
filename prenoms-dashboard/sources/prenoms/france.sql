-- Fichier national : une ligne par sexe × prénom × année (prénoms rares inclus pour les totaux)
select sexe, prenom, libelle, annee::integer as annee, nombre::integer as nombre,
       prenom = '_PRENOMS_RARES' as est_rare
from v_france
where annee is not null
