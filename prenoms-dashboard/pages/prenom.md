---
title: Explorer un prénom
description: Évolution, pic de popularité et géographie d'un prénom
sidebar_position: 2
---

```sql catalogue
select prenom, libelle_recherche from prenoms.catalogue order by total desc
```

```sql decennies
select 'Toute la période' as libelle, 0 as debut, 9999 as fin, 0 as ordre
union all
select distinct (annee // 10 * 10)::varchar || 's', annee // 10 * 10, annee // 10 * 10 + 9, annee // 10 * 10
from prenoms.naissances
order by ordre
```

<Grid cols=3>
<Dropdown name=prenom data={catalogue} value=prenom label=libelle_recherche title="Prénom" defaultValue="MARIE" />
<ButtonGroup name=sexe title="Sexe">
    <ButtonGroupItem valueLabel="Tous" value="T" default />
    <ButtonGroupItem valueLabel="Filles" value="F" />
    <ButtonGroupItem valueLabel="Garçons" value="M" />
</ButtonGroup>
<Dropdown name=periode data={decennies} value=debut label=libelle order=ordre title="Période (carte & départements)" defaultValue=0 />
</Grid>

```sql fiche
select * from prenoms.catalogue where prenom = '${inputs.prenom.value}'
```

```sql meilleur_rang
select min(rang) as rang, arg_min(annee, rang) as annee
from prenoms.rangs
where prenom = '${inputs.prenom.value}'
  and ('${inputs.sexe}' = 'T' or sexe = '${inputs.sexe}')
```

# <Value data={fiche} column=libelle />

<Grid cols=4>
<BigValue data={fiche} value=total title="Naissances depuis 1900" fmt='#,##0' />
<BigValue data={fiche} value=annee_pic title="Année du pic" fmt=id comparison=naissances_pic comparisonTitle="naissances cette année-là" comparisonFmt='#,##0' comparisonDelta=false />
<BigValue data={meilleur_rang} value=rang title="Meilleur rang national" fmt='"n°"0' comparison=annee comparisonTitle="atteint en" comparisonFmt=id comparisonDelta=false />
<BigValue data={fiche} value=part_f title="Part de filles" fmt='0%' comparison=genre comparisonTitle="" comparisonDelta=false />
</Grid>

{#if fiche.length && fiche[0].genre === 'Mixte'}
<Alert status="info"><b><Value data={fiche} column=libelle /></b> est un prénom <b>mixte</b> : utilisez le sélecteur « Sexe » pour isoler filles ou garçons.</Alert>
{/if}

## Évolution depuis 1900

```sql evolution
select annee, case sexe when 'F' then 'Filles' else 'Garçons' end as sexe, nombre as naissances, pour_mille / 1000 as part, rang
from prenoms.rangs
where prenom = '${inputs.prenom.value}'
  and ('${inputs.sexe}' = 'T' or sexe = '${inputs.sexe}')
order by annee
```

<Tabs>
<Tab label="Naissances">
<BarChart
    data={evolution}
    x=annee y=naissances series=sexe
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    xFmt=id yFmt='#,##0'
    title="Naissances par année"
/>
</Tab>
<Tab label="Part des naissances">
<LineChart
    data={evolution}
    x=annee y=part series=sexe
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    xFmt=id yFmt='0.00%'
    title="Part des naissances du même sexe"
    subtitle="Corrige l'effet du nombre total de naissances (guerres, baby-boom)"
/>
</Tab>
<Tab label="Rang">
<LineChart
    data={evolution}
    x=annee y=rang series=sexe
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    xFmt=id yFmt='0'
    yLog=true
    title="Rang national (échelle logarithmique, 1 = prénom le plus donné)"
/>
</Tab>
</Tabs>

## Où ce prénom est-il donné ?

```sql geo
with p as (
  select dpt, sum(nombre) as n
  from prenoms.departements_detail
  where prenom = '${inputs.prenom.value}'
    and ('${inputs.sexe}' = 'T' or sexe = '${inputs.sexe}')
    and annee between ${inputs.periode.value} and ${inputs.periode.value} + case when ${inputs.periode.value} = 0 then 9999 else 9 end
  group by dpt
),
t as (
  select dpt, sum(naissances) as total
  from prenoms.naissances_dpt
  where ('${inputs.sexe}' = 'T' or sexe = '${inputs.sexe}')
    and annee in (select distinct annee from prenoms.departements_detail
                  where prenom = '${inputs.prenom.value}')
    and annee between ${inputs.periode.value} and ${inputs.periode.value} + case when ${inputs.periode.value} = 0 then 9999 else 9 end
  group by dpt
)
select d.dpt, d.nom, d.region, coalesce(p.n, 0) as naissances,
       1000.0 * coalesce(p.n, 0) / t.total as pour_mille,
       (1000.0 * coalesce(p.n, 0) / t.total) / (1000.0 * sum(coalesce(p.n, 0)) over () / sum(t.total) over ()) as indice
from prenoms.departements d
join t using (dpt)
left join p using (dpt)
order by pour_mille desc
```

<Grid cols=2>
<FranceMap
    data={geo}
    code=dpt
    value=pour_mille
    legendTitle="‰ des naissances"
    title="Fréquence du prénom par département"
    subtitle="Naissances pour 1 000 naissances du département, sur les années où le prénom est donné"
    fmt={(v) => v == null ? '—' : Number(v).toLocaleString('fr-FR', {maximumFractionDigits: 2}) + ' ‰'}
    extra={(r) => Number(r.naissances).toLocaleString('fr-FR') + ' naissances · indice ' + Number(r.indice).toFixed(2)}
/>
<div>

**Départements où il est le plus surreprésenté**

<DataTable data={geo} rows=12 compact=true search=true>
    <Column id=nom title="Département" />
    <Column id=naissances fmt='#,##0' />
    <Column id=pour_mille title="‰" fmt='0.00' contentType=colorscale colorScale=#2a78d6 />
    <Column id=indice title="Indice" fmt='0.00' description="1 = moyenne nationale ; 2 = deux fois plus fréquent que la moyenne" />
</DataTable>

</div>
</Grid>

## Comparer plusieurs prénoms

```sql comparaison
select annee, libelle, sum(nombre) as naissances
from prenoms.france
where prenom in ${inputs.comparer.value} and not est_rare
group by all
order by annee
```

<Dropdown name=comparer data={catalogue} value=prenom label=libelle_recherche multiple=true title="Prénoms à comparer" defaultValue={['LÉA', 'EMMA', 'JADE', 'LOUISE']} />

<LineChart
    data={comparaison}
    x=annee y=naissances series=libelle
    xFmt=id yFmt='#,##0'
    title="Naissances par année (filles et garçons confondus)"
/>
