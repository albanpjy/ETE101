-- Référentiel limité aux codes présents dans les données
-- (selon l'édition, la Corse est codée « 20 » ou « 2A »/« 2B »)
select code as dpt, nom, region, code || ' · ' || nom as libelle_dpt
from v_departements
where code in (select distinct dpt from v_departements_detail)
order by code
