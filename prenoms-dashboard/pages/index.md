---
title: Les prénoms en France depuis 1900
description: Tableau de bord interactif du Fichier des prénoms de l'INSEE (data.gouv.fr)
sidebar_position: 1
---

```sql meta
select * from prenoms.meta
```

{#if meta[0]?.demo}
<Alert status="warning">
<b>Mode démonstration :</b> les chiffres affichés sont <b>fictifs</b>. Lancez <code>npm run data</code> pour charger le vrai fichier INSEE depuis data.gouv.fr.
</Alert>
{/if}

Chaque année, l'INSEE publie le nombre de naissances par prénom, sexe et département depuis 1900, à partir de l'état civil.
Ce tableau de bord permet d'explorer **<Value data={kpi} column=naissances fmt='#,##0' />** naissances
et **<Value data={kpi} column=prenoms fmt='#,##0' />** prénoms différents, de <Value data={meta} column=annee_min fmt=id /> à <Value data={meta} column=annee_max fmt=id />.

```sql kpi
select
  (select sum(naissances) from prenoms.naissances) as naissances,
  (select count(*) from prenoms.catalogue) as prenoms,
  (select annee from prenoms.naissances group by annee order by sum(naissances) desc limit 1) as annee_record,
  (select max(s) from (select sum(naissances) s from prenoms.naissances group by annee)) as naissances_record,
  (select libelle from prenoms.catalogue where genre <> 'Masculin' order by total_f desc limit 1) as top_f,
  (select max(total_f) from prenoms.catalogue) as top_f_n,
  (select libelle from prenoms.catalogue where genre <> 'Féminin' order by total_m desc limit 1) as top_m,
  (select max(total_m) from prenoms.catalogue) as top_m_n
```

<Grid cols=4>
<BigValue data={kpi} value=naissances title="Naissances recensées" fmt='#,##0.0,,"M"' />
<BigValue data={kpi} value=annee_record title="Année record" fmt=id comparison=naissances_record comparisonTitle="naissances" comparisonFmt='#,##0' comparisonDelta=false />
<BigValue data={kpi} value=top_f title="Prénom féminin n°1 (cumul)" comparison=top_f_n comparisonTitle="naissances" comparisonFmt='#,##0' comparisonDelta=false />
<BigValue data={kpi} value=top_m title="Prénom masculin n°1 (cumul)" comparison=top_m_n comparisonTitle="naissances" comparisonFmt='#,##0' comparisonDelta=false />
</Grid>

## Les naissances au fil du siècle

```sql naissances_annee
select annee, case sexe when 'F' then 'Filles' else 'Garçons' end as sexe, naissances
from prenoms.naissances
order by annee
```

<AreaChart
    data={naissances_annee}
    x=annee
    y=naissances
    series=sexe
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    xFmt=id
    yFmt='#,##0'
    title="Naissances recensées par année"
    subtitle="Les creux de 1915-1919 et 1940-1945 et le baby-boom d'après-guerre se lisent immédiatement"
/>

## Le palmarès d'une année

<Slider name=annee title="Année" data={meta} minColumn=annee_min maxColumn=annee_max defaultValue=annee_max fmt=id size=full />

```sql top_annee
with r as (
  select sexe, libelle, nombre, rang, pour_mille,
         lag(rang) over (partition by sexe, prenom order by annee) as rang_prec
  from prenoms.rangs
  where annee in (${inputs.annee} - 1, ${inputs.annee})
  qualify annee = ${inputs.annee}
)
select sexe, rang, libelle as prenom, nombre as naissances, pour_mille / 1000 as part,
       rang_prec - rang as gain_rang
from r
where rang <= 15
order by sexe, rang
```

```sql top_f
select * from ${top_annee} where sexe = 'F'
```

```sql top_m
select * from ${top_annee} where sexe = 'M'
```

<Grid cols=2>
<div>

### Filles en {inputs.annee}

<DataTable data={top_f} rows=15 compact=true>
    <Column id=rang title="#" />
    <Column id=prenom title="Prénom" />
    <Column id=naissances fmt='#,##0' contentType=bar barColor="#f6c2ab" />
    <Column id=part title="Part" fmt='0.00%' />
    <Column id=gain_rang title="Δ rang" contentType=delta fmt='+0;-0;=' />
</DataTable>

</div>
<div>

### Garçons en {inputs.annee}

<DataTable data={top_m} rows=15 compact=true>
    <Column id=rang title="#" />
    <Column id=prenom title="Prénom" />
    <Column id=naissances fmt='#,##0' contentType=bar barColor="#b5d2f4" />
    <Column id=part title="Part" fmt='0.00%' />
    <Column id=gain_rang title="Δ rang" contentType=delta fmt='+0;-0;=' />
</DataTable>

</div>
</Grid>

<small>Δ rang : places gagnées (+) ou perdues (−) par rapport à l'année précédente.</small>

## Une diversité qui explose

Les parents choisissent des prénoms de plus en plus variés : le nombre de prénoms distincts attribués chaque année a été multiplié, tandis que le poids des 10 prénoms les plus donnés s'est effondré.

```sql diversite
select annee, case sexe when 'F' then 'Filles' else 'Garçons' end as sexe, prenoms_distincts
from prenoms.naissances
order by annee
```

```sql concentration
select annee, case sexe when 'F' then 'Filles' else 'Garçons' end as sexe,
       sum(pour_mille) filter (where rang <= 10) / 1000 as part_top10
from prenoms.rangs
group by all
order by annee
```

<Grid cols=2>
<LineChart
    data={diversite}
    x=annee y=prenoms_distincts series=sexe
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    xFmt=id yFmt='#,##0'
    title="Prénoms distincts attribués par an"
/>
<LineChart
    data={concentration}
    x=annee y=part_top10 series=sexe
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    xFmt=id yFmt='0%'
    title="Part des naissances portant un prénom du top 10"
/>
</Grid>

## Les n°1 de chaque année

```sql numero_un
select annee,
       max(libelle) filter (where sexe = 'F' and rang = 1) as fille,
       max(nombre) filter (where sexe = 'F' and rang = 1) as n_fille,
       max(libelle) filter (where sexe = 'M' and rang = 1) as garcon,
       max(nombre) filter (where sexe = 'M' and rang = 1) as n_garcon
from prenoms.rangs
where rang = 1
group by annee
order by annee desc
```

<DataTable data={numero_un} rows=15 search=true>
    <Column id=annee title="Année" fmt=id />
    <Column id=fille title="Fille n°1" />
    <Column id=n_fille title="Naissances" fmt='#,##0' />
    <Column id=garcon title="Garçon n°1" />
    <Column id=n_garcon title="Naissances" fmt='#,##0' />
</DataTable>

## Sources & méthode

- **Données** : INSEE, *Fichier des prénoms* (état civil), diffusé sur [data.gouv.fr](https://www.data.gouv.fr/fr/datasets/fichier-des-prenoms-depuis-1900/) — fichier national et fichier départemental (niveau le plus fin). Source chargée : <Value data={meta} column=source />.
- **Secret statistique** : au niveau national, les prénoms donnés moins de 3 fois sur une année sont regroupés sous « prénoms rares » ; au niveau départemental, un prénom n'apparaît que s'il a été donné au moins 3 fois sur une année et 20 fois sur la période. Les totaux de naissances incluent ces prénoms rares.
- **Chaîne de traitement** : téléchargement et normalisation avec DuckDB (`scripts/ingest.py`) → fichiers Parquet (`data/`) → requêtes Evidence (`sources/prenoms/`).
- Fond de carte : [svg-maps](https://github.com/VictorCazanave/svg-maps) (CC-BY-4.0).
