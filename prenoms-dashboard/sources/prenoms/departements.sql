select code as dpt, nom, region, code || ' · ' || nom as libelle_dpt
from v_departements
order by code
