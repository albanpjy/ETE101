# Les prénoms en France depuis 1900 : tableau de bord Evidence

Tableau de bord interactif construit avec **[Evidence](https://evidence.dev)**, **DuckDB** et **Parquet**, à partir du
*Fichier des prénoms* de l'INSEE diffusé sur [data.gouv.fr](https://www.data.gouv.fr/fr/datasets/fichier-des-prenoms-depuis-1900/).
On y trouve toutes les données, jusqu'au niveau le plus fin : **sexe × prénom × année × département**.

## Démarrage

```bash
cd prenoms-dashboard
npm install
npm run data        # télécharge les fichiers INSEE et produit data/*.parquet (DuckDB)
npm run sources     # Evidence exécute les requêtes de sources/prenoms/ sur ces Parquet
npm run dev         # http://localhost:3000
```

Pas d'accès réseau à data.gouv.fr ? Plusieurs solutions :

```bash
python3 scripts/ingest.py --dpt-file ~/Téléchargements/dpt2023_csv.zip --nat-file ~/Téléchargements/nat2023_csv.zip
python3 scripts/ingest.py --dpt-url https://…/dpt.zip           # URL explicite
python3 scripts/ingest.py --demo                                 # données FICTIVES, pour tester l'interface
```

Prérequis : Node ≥ 18 et Python 3 avec `duckdb` (`pip install duckdb`).
Pendant `npm run sources` et dans le navigateur, DuckDB-WASM télécharge son extension Parquet depuis
`extensions.duckdb.org` : ce domaine doit donc être joignable.

## Architecture

```
data.gouv.fr (CSV INSEE, zip)
   │  scripts/ingest.py : découverte via l'API data.gouv, téléchargement,
   │                      normalisation DuckDB (schémas des éditions 2019 → 2025)
   ▼
data/prenoms_departements.parquet   sexe, prenom, libelle, annee, dpt, nombre   (niveau le plus fin)
data/prenoms_france.parquet         sexe, prenom, libelle, annee, nombre
data/departements.parquet           code, nom, region
data/meta.parquet                   source, édition, URL, années couvertes
   │  sources/prenoms/initialize.sql : vues DuckDB read_parquet(...)
   │  sources/prenoms/*.sql          : tables Evidence (détail + agrégats)
   ▼
pages/*.md : pages Evidence (SQL dans le navigateur via DuckDB-WASM)
components/FranceMap.svelte : carte choroplèthe des départements (SVG, DROM en encarts)
```

| Table Evidence | Contenu |
|---|---|
| `prenoms.departements_detail` | niveau le plus fin : sexe × prénom × année × département |
| `prenoms.france` | fichier national (prénoms rares inclus pour les totaux) |
| `prenoms.rangs` | rang national et fréquence (‰) de chaque prénom par année et sexe |
| `prenoms.catalogue` | une ligne par prénom : total, pic, genre (féminin / masculin / mixte) |
| `prenoms.naissances`, `prenoms.naissances_dpt` | totaux de naissances (France, départements) |
| `prenoms.departements`, `prenoms.meta` | référentiels |

## Pages

1. **Vue d'ensemble** : chiffres clés, naissances depuis 1900, palmarès d'une année (curseur), diversité des prénoms, n°1 de chaque année.
2. **Explorer un prénom** : recherche parmi tous les prénoms, évolution (naissances, part, rang), carte départementale avec indice de surreprésentation, comparateur multi-prénoms.
3. **Explorer un département** : chiffres clés, carte de situation, naissances, palmarès par décennie, prénoms typiques (indice de spécificité), n°1 de chaque décennie.
4. **La France des prénoms** : carte du prénom n°1 par département, carte des naissances, carte de la part des prénoms « rares » localement.
5. **Tendances & curiosités** : plus fortes hausses et baisses entre deux années, course au sommet (heatmap), prénoms météores, prénoms mixtes, longueur moyenne et prénoms composés.

## Notes sur les données

- Secret statistique INSEE : au niveau national, les prénoms attribués moins de 3 fois une année sont regroupés en `_PRENOMS_RARES`.
  Au niveau départemental, un prénom n'apparaît que s'il a été donné au moins 3 fois sur l'année et 20 fois sur la période ; sinon l'année et/ou le département sont masqués (`XXXX` / `XX`).
  Les totaux de naissances incluent ces prénoms rares, les classements les excluent.
- Les fichiers bruts (`data/raw/`) et les Parquet (`data/*.parquet`) ne sont pas versionnés : on les régénère avec `npm run data`.
- Fond de carte : [svg-maps](https://github.com/VictorCazanave/svg-maps) (`@svg-maps/france.departments`, CC-BY-4.0).
