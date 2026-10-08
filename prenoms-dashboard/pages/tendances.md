---
title: Tendances & curiosités
description: Prénoms en vogue, en déclin, météores, prénoms mixtes, composés et longueur des prénoms
sidebar_position: 5
---

```sql meta
select *, greatest(annee_min, annee_max - 15) as annee_debut from prenoms.meta
```

## Qui monte, qui descend ?

<Grid cols=3>
<Slider name=debut title="Année de départ" data={meta} minColumn=annee_min maxColumn=annee_max defaultValue=annee_debut fmt=id />
<Slider name=fin title="Année d'arrivée" data={meta} minColumn=annee_min maxColumn=annee_max defaultValue=annee_max fmt=id />
<ButtonGroup name=sexe title="Sexe">
    <ButtonGroupItem valueLabel="Filles" value="F" default />
    <ButtonGroupItem valueLabel="Garçons" value="M" />
</ButtonGroup>
</Grid>

```sql evolutions
with a as (
  select prenom, libelle, nombre, pour_mille, rang from prenoms.rangs
  where annee = ${inputs.debut} and sexe = '${inputs.sexe}'
),
b as (
  select prenom, libelle, nombre, pour_mille, rang from prenoms.rangs
  where annee = ${inputs.fin} and sexe = '${inputs.sexe}'
)
select coalesce(b.libelle, a.libelle) as prenom,
       coalesce(a.nombre, 0) as naissances_debut,
       coalesce(b.nombre, 0) as naissances_fin,
       coalesce(b.pour_mille, 0) - coalesce(a.pour_mille, 0) as ecart_pour_mille,
       a.rang as rang_debut, b.rang as rang_fin
from a full join b using (prenom)
```

```sql hausses
select * from ${evolutions} order by ecart_pour_mille desc limit 12
```

```sql baisses
select * from ${evolutions} order by ecart_pour_mille asc limit 12
```

<Grid cols=2>
<BarChart
    data={hausses}
    x=prenom y=ecart_pour_mille
    swapXY=true sort=false
    fillColor="#1baf7a"
    yFmt='+0.0'
    title="Plus fortes progressions"
    subtitle="Écart de fréquence, en naissances pour 1 000"
/>
<BarChart
    data={baisses}
    x=prenom y=ecart_pour_mille
    swapXY=true sort=false
    fillColor="#e34948"
    yFmt='+0.0;-0.0'
    title="Plus fortes baisses"
    subtitle="Écart de fréquence, en naissances pour 1 000"
/>
</Grid>

<Details title="Tableau complet des évolutions">
<DataTable data={evolutions} rows=15 search=true sort="ecart_pour_mille desc">
    <Column id=prenom title="Prénom" />
    <Column id=rang_debut title="Rang départ" />
    <Column id=rang_fin title="Rang arrivée" />
    <Column id=naissances_debut title="Naissances départ" fmt='#,##0' />
    <Column id=naissances_fin title="Naissances arrivée" fmt='#,##0' />
    <Column id=ecart_pour_mille title="Écart (‰)" fmt='+0.00;-0.00' contentType=delta />
</DataTable>
</Details>

## La course au sommet

Fréquence (pour 1 000 naissances) des 15 prénoms les plus donnés l'année d'arrivée, sur les 30 années précédentes.

```sql course
with top as (
  select prenom from prenoms.rangs
  where annee = ${inputs.fin} and sexe = '${inputs.sexe}' and rang <= 15
)
select r.annee, r.libelle as prenom, r.pour_mille, r.rang
from prenoms.rangs r
where r.prenom in (select prenom from top) and r.sexe = '${inputs.sexe}'
  and r.annee between ${inputs.fin} - 30 and ${inputs.fin}
order by r.annee
```

<Heatmap
    data={course}
    x=annee y=prenom value=pour_mille
    xFmt=id valueFmt='0.0'
    colorScale={['#dbe9fa', '#2a78d6', '#13427c']}
    title="Le top 15 actuel, 30 ans d'histoire"
    xLabelWrap=false
/>

## Les prénoms météores

Certains prénoms connaissent une gloire fulgurante : une grande partie de leurs porteurs sont nés la même année. On mesure ici la part du total des naissances concentrée sur l'année du pic (prénoms donnés au moins 5 000 fois, dont le pic remonte à plus de 5 ans).

```sql meteores
select libelle as prenom, genre, total, annee_pic, naissances_pic,
       naissances_pic::double / total as concentration
from prenoms.catalogue
where total >= 5000
  -- un pic sur les dernières années signale un prénom encore en hausse, pas un météore
  and annee_pic <= (select annee_max - 5 from prenoms.meta)
order by concentration desc
limit 20
```

<DataTable data={meteores} rows=20 compact=true>
    <Column id=prenom title="Prénom" />
    <Column id=genre title="Genre" />
    <Column id=annee_pic title="Année du pic" fmt=id />
    <Column id=naissances_pic title="Naissances au pic" fmt='#,##0' />
    <Column id=total title="Total" fmt='#,##0' />
    <Column id=concentration title="Part au pic" fmt='0.0%' contentType=bar barColor="#f6c2ab" />
</DataTable>

## Les prénoms mixtes

```sql mixtes
select libelle as prenom, total, part_f, 1 - part_f as part_m
from prenoms.catalogue
where genre = 'Mixte' and total >= 2000
order by total desc
limit 20
```

```sql mixtes_long
select prenom, 'Filles' as sexe, part_f as part, total from ${mixtes}
union all
select prenom, 'Garçons', part_m, total from ${mixtes}
order by total desc
```

<BarChart
    data={mixtes_long}
    x=prenom y=part series=sexe
    type=stacked100
    swapXY=true
    sort=false
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    yFmt='0%'
    title="Les 20 prénoms mixtes les plus portés"
    subtitle="Prénoms dont 10 à 90 % des porteurs sont des filles"
/>

## Des prénoms plus courts… et moins composés

```sql forme
select annee, case sexe when 'F' then 'Filles' else 'Garçons' end as sexe,
       sum(length(libelle) * nombre)::double / sum(nombre) as longueur_moyenne,
       coalesce(sum(nombre) filter (where libelle like '%-%'), 0)::double / sum(nombre) as part_composes
from prenoms.rangs
group by all
order by annee
```

<Grid cols=2>
<LineChart
    data={forme}
    x=annee y=longueur_moyenne series=sexe
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    xFmt=id yFmt='0.0'
    title="Longueur moyenne du prénom (lettres)"
/>
<LineChart
    data={forme}
    x=annee y=part_composes series=sexe
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    xFmt=id yFmt='0%'
    title="Part des prénoms composés (avec trait d'union)"
/>
</Grid>
