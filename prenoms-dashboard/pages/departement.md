---
title: Explorer un département
description: Palmarès, prénoms typiques et évolution des naissances dans chaque département
sidebar_position: 3
---

```sql liste_dpt
select dpt, libelle_dpt from prenoms.departements order by dpt
```

```sql decennies
select distinct annee // 10 * 10 as debut, (annee // 10 * 10)::varchar || 's' as libelle
from prenoms.naissances_dpt
order by debut desc
```

<Grid cols=3>
<Dropdown name=dpt data={liste_dpt} value=dpt label=libelle_dpt title="Département" defaultValue="75" />
<Dropdown name=decennie data={decennies} value=debut label=libelle order="debut desc" title="Décennie" defaultValue=2010 />
<ButtonGroup name=sexe title="Sexe">
    <ButtonGroupItem valueLabel="Filles" value="F" default />
    <ButtonGroupItem valueLabel="Garçons" value="M" />
</ButtonGroup>
</Grid>

```sql info
select d.*,
  (select sum(naissances) from prenoms.naissances_dpt where dpt = '${inputs.dpt.value}') as naissances,
  (select count(distinct prenom) from prenoms.departements_detail where dpt = '${inputs.dpt.value}') as prenoms,
  (select libelle from prenoms.departements_detail where dpt = '${inputs.dpt.value}' and sexe = 'F'
     group by libelle order by sum(nombre) desc limit 1) as top_f,
  (select libelle from prenoms.departements_detail where dpt = '${inputs.dpt.value}' and sexe = 'M'
     group by libelle order by sum(nombre) desc limit 1) as top_m
from prenoms.departements d
where d.dpt = '${inputs.dpt.value}'
```

# <Value data={info} column=nom /> <span class="text-base-content-muted text-xl">(<Value data={info} column=dpt />) · <Value data={info} column=region /></span>

<Grid cols=4>
<BigValue data={info} value=naissances title="Naissances recensées" fmt='#,##0' />
<BigValue data={info} value=prenoms title="Prénoms distincts" fmt='#,##0' />
<BigValue data={info} value=top_f title="Fille n°1 (cumul)" />
<BigValue data={info} value=top_m title="Garçon n°1 (cumul)" />
</Grid>

<FranceMap
    data={liste_dpt}
    code=dpt
    value=dpt
    nameCol=libelle_dpt
    highlight={inputs.dpt.value}
    mode=locator
    height=220
/>

## Les naissances dans le département

```sql naissances
select annee, case sexe when 'F' then 'Filles' else 'Garçons' end as sexe, naissances
from prenoms.naissances_dpt
where dpt = '${inputs.dpt.value}'
order by annee
```

<AreaChart
    data={naissances}
    x=annee y=naissances series=sexe
    seriesColors={{'Filles': '#eb6834', 'Garçons': '#2a78d6'}}
    xFmt=id yFmt='#,##0'
    title="Naissances recensées par année"
/>

## Palmarès de la décennie

```sql palmares
with dpt as (
  select prenom, libelle, sum(nombre) as n
  from prenoms.departements_detail
  where dpt = '${inputs.dpt.value}' and sexe = '${inputs.sexe}'
    and annee between ${inputs.decennie.value} and ${inputs.decennie.value} + 9
  group by all
)
select row_number() over (order by dpt.n desc) as rang,
       dpt.libelle as prenom, dpt.n as naissances,
       dpt.n / sum(dpt.n) over () as part
from dpt
qualify rang <= 20
order by rang
```

<DataTable data={palmares} rows=20 compact=true>
    <Column id=rang title="#" />
    <Column id=prenom title="Prénom" />
    <Column id=naissances fmt='#,##0' contentType=bar barColor="#b5d2f4" />
    <Column id=part title="Part (prénoms publiés)" fmt='0.0%' />
</DataTable>

## Les prénoms typiques du département

Un **indice de spécificité** compare la fréquence d'un prénom dans le département à sa fréquence nationale sur la même décennie (2 = deux fois plus fréquent qu'en moyenne). Seuls les prénoms donnés au moins 30 fois dans le département sont retenus.

```sql specifiques
with loc as (
  select prenom, libelle, sum(nombre) as n
  from prenoms.departements_detail
  where dpt = '${inputs.dpt.value}' and sexe = '${inputs.sexe}'
    and annee between ${inputs.decennie.value} and ${inputs.decennie.value} + 9
  group by all
),
loc_tot as (
  select sum(naissances) as t from prenoms.naissances_dpt
  where dpt = '${inputs.dpt.value}' and sexe = '${inputs.sexe}'
    and annee between ${inputs.decennie.value} and ${inputs.decennie.value} + 9
),
nat as (
  select prenom, sum(nombre) as n from prenoms.france
  where sexe = '${inputs.sexe}' and annee between ${inputs.decennie.value} and ${inputs.decennie.value} + 9
  group by all
),
nat_tot as (
  select sum(naissances) as t from prenoms.naissances
  where sexe = '${inputs.sexe}' and annee between ${inputs.decennie.value} and ${inputs.decennie.value} + 9
)
select loc.libelle as prenom, loc.n as naissances,
       1000.0 * loc.n / loc_tot.t as pour_mille_local,
       1000.0 * nat.n / nat_tot.t as pour_mille_national,
       (loc.n / loc_tot.t) / (nat.n / nat_tot.t) as indice
from loc join nat using (prenom), loc_tot, nat_tot
where loc.n >= 30
order by indice desc
limit 15
```

<BarChart
    data={specifiques}
    x=prenom y=indice
    swapXY=true
    sort=false
    yFmt='0.0'
    fillColor="#1baf7a"
    title="Indice de spécificité (top 15)"
    subtitle="Rapport entre la fréquence locale et la fréquence nationale"
/>

## Les n°1 de chaque décennie

```sql numero_un
with r as (
  select annee // 10 * 10 as decennie, sexe, libelle, sum(nombre) as n
  from prenoms.departements_detail
  where dpt = '${inputs.dpt.value}'
  group by 1, 2, 3
  qualify row_number() over (partition by decennie, sexe order by n desc) = 1
)
select decennie::varchar || 's' as decennie,
       max(libelle) filter (where sexe = 'F') as fille, max(n) filter (where sexe = 'F') as n_fille,
       max(libelle) filter (where sexe = 'M') as garcon, max(n) filter (where sexe = 'M') as n_garcon
from r
group by decennie
order by decennie desc
```

<DataTable data={numero_un} rows=13 compact=true>
    <Column id=decennie title="Décennie" />
    <Column id=fille title="Fille n°1" />
    <Column id=n_fille title="Naissances" fmt='#,##0' />
    <Column id=garcon title="Garçon n°1" />
    <Column id=n_garcon title="Naissances" fmt='#,##0' />
</DataTable>
