-- Vues DuckDB sur les fichiers Parquet produits par `npm run data` (scripts/ingest.py)
create or replace view v_departements_detail as select * from read_parquet('data/prenoms_departements.parquet');
create or replace view v_france as select * from read_parquet('data/prenoms_france.parquet');
create or replace view v_departements as select * from read_parquet('data/departements.parquet');
create or replace view v_meta as select * from read_parquet('data/meta.parquet');
