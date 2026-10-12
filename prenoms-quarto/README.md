# Les prénoms en France depuis 1900 : tableau de bord Quarto (R + Shiny)

Jumeau R du tableau de bord Evidence (`../prenoms-dashboard/`) : **Quarto Dashboard** avec **Shiny**,
**DuckDB** et **Parquet**, à partir du *Fichier des prénoms* de l'INSEE
([data.gouv.fr](https://www.data.gouv.fr/fr/datasets/fichier-des-prenoms-depuis-1900/)),
jusqu'au niveau le plus fin : **sexe × prénom × année × département**.

## Prérequis

- **R ≥ 4.2** et **Quarto ≥ 1.4** (RStudio récent inclut Quarto)
- Les paquets R : `Rscript install.R`

## Lancer le tableau de bord

Dans un terminal, depuis ce dossier :

```bash
Rscript install.R          # une seule fois
quarto serve prenoms.qmd   # ouvre http://localhost:XXXX dans le navigateur
```

Ou dans **RStudio** : ouvrez `prenoms-quarto.Rproj`, puis `prenoms.qmd`, et cliquez sur **Run Document**.

Les données (édition INSEE 2022, années 1900 à 2022) sont déjà dans `data/` : aucun téléchargement n'est nécessaire.

## Mettre à jour les données

```bash
Rscript R/ingest.R                                        # découverte automatique sur data.gouv.fr
Rscript R/ingest.R --dpt-file dpt2022_csv.zip             # archive déjà téléchargée
Rscript R/ingest.R --dpt-file dpt2022_csv.zip --nat-file nat2022_csv.zip   # + fichier national (totaux exacts)
```

## Pages

1. **Vue d'ensemble** : chiffres clés, naissances depuis 1900, palmarès d'une année, diversité des prénoms, n°1 de chaque année.
2. **Explorer un prénom** : recherche parmi 16 000 prénoms, évolution (naissances, part, rang), carte départementale et indice de surreprésentation, comparateur.
3. **Explorer un département** : chiffres clés, carte de situation, naissances, palmarès par décennie, prénoms typiques, n°1 de chaque décennie.
4. **La France des prénoms** : carte du prénom n°1 par département, carte des naissances, carte des prénoms « rares ».
5. **Tendances & curiosités** : hausses et baisses entre deux années, course au sommet (heatmap), prénoms météores, prénoms mixtes, longueur des prénoms et prénoms composés.

## Organisation

```
prenoms.qmd              tableau de bord (pages, mise en page, logique Shiny)
styles.scss              thème (palette, cartes, tuiles)
R/data.R                 DuckDB en mémoire sur les Parquet + tables dérivées (rangs, catalogue, totaux)
R/viz.R                  palette, formats français, graphiques plotly, carte des départements
R/ingest.R               téléchargement + normalisation INSEE → Parquet (DuckDB)
R/contours.R             conversion du fond de carte SVG en polygones (data/departements_contours.csv)
data/                    Parquet normalisés, référentiel et contours des départements
```

## Notes sur les données

- Secret statistique : au niveau départemental, un prénom n'apparaît que s'il a été donné au moins 3 fois sur l'année
  et 20 fois sur la période. Sinon l'année ou le département sont masqués. Les totaux incluent ces naissances, les classements non.
- Sans fichier national, les séries nationales sont agrégées depuis le fichier départemental : les naissances dont l'année
  est masquée (≈ 9 M) n'y figurent pas, d'où des totaux annuels légèrement sous-estimés.
- Dans cette édition, la Corse est codée « 20 » sur toute la période : la carte la reporte sur 2A et 2B.
- Paris : la forte baisse de 1968 correspond à la création des départements de la petite couronne (92, 93, 94).
- Fond de carte : [svg-maps](https://github.com/VictorCazanave/svg-maps) (CC-BY-4.0).
