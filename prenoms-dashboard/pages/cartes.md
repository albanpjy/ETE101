---
title: La France des prénoms
description: Cartes départementales du prénom n°1, des naissances et de la diversité
sidebar_position: 4
---

```sql meta
select * from prenoms.meta
```

<Grid cols=2>
<Slider name=annee title="Année" data={meta} minColumn=annee_min maxColumn=annee_max defaultValue=annee_max fmt=id size=full />
<ButtonGroup name=sexe title="Sexe">
    <ButtonGroupItem valueLabel="Filles" value="F" default />
    <ButtonGroupItem valueLabel="Garçons" value="M" />
</ButtonGroup>
</Grid>

## Le prénom n°1 de chaque département en {inputs.annee}

```sql top_dpt
with r as (
  select dpt, libelle, nombre,
         row_number() over (partition by dpt order by nombre desc, libelle) as rk,
         nombre / sum(nombre) over (partition by dpt) as part_publies
  from prenoms.departements_detail
  where annee = ${inputs.annee} and sexe = '${inputs.sexe}'
)
select r.dpt, d.nom, d.region, r.libelle as prenom, r.nombre as naissances,
       r.nombre::double / t.naissances as part
from r
join prenoms.departements d using (dpt)
join prenoms.naissances_dpt t on t.dpt = r.dpt and t.annee = ${inputs.annee} and t.sexe = '${inputs.sexe}'
where rk = 1
order by r.dpt
```

```sql top_dpt_resume
select prenom, count(*) as departements, sum(naissances) as naissances
from ${top_dpt}
group by prenom
order by departements desc, naissances desc
```

<Grid cols=2>
<FranceMap
    data={top_dpt}
    code=dpt
    value=naissances
    category=prenom
    legendTitle="naissances :"
    title="Prénom le plus donné par département"
    subtitle="Les 5 prénoms qui l'emportent le plus souvent sont colorés, les autres en gris"
    fmt={(v) => Number(v).toLocaleString('fr-FR')}
    extra={(r) => (100 * r.part).toLocaleString('fr-FR', {maximumFractionDigits: 1}) + ' % des naissances du département'}
/>
<div>

**Nombre de départements remportés**

<DataTable data={top_dpt_resume} rows=10 compact=true>
    <Column id=prenom title="Prénom" />
    <Column id=departements title="Départements" contentType=bar barColor="#b5d2f4" />
    <Column id=naissances title="Naissances" fmt='#,##0' />
</DataTable>

<Details title="Voir le détail par département">
<DataTable data={top_dpt} rows=10 compact=true search=true>
    <Column id=dpt title="Code" />
    <Column id=nom title="Département" />
    <Column id=prenom title="Prénom n°1" />
    <Column id=naissances fmt='#,##0' />
    <Column id=part title="Part" fmt='0.0%' />
</DataTable>
</Details>

</div>
</Grid>

## Naissances et diversité en {inputs.annee}

```sql indicateurs_dpt
with det as (
  select dpt, count(distinct prenom) as prenoms_distincts, sum(nombre) as naissances_publiees
  from prenoms.departements_detail
  where annee = ${inputs.annee} and sexe = '${inputs.sexe}'
  group by dpt
)
select d.dpt, d.nom, t.naissances,
       det.prenoms_distincts,
       1 - det.naissances_publiees::double / t.naissances as part_rares,
       1000.0 * det.prenoms_distincts / t.naissances as diversite
from prenoms.departements d
join prenoms.naissances_dpt t on t.dpt = d.dpt and t.annee = ${inputs.annee} and t.sexe = '${inputs.sexe}'
left join det on det.dpt = d.dpt
```

<Grid cols=2>
<FranceMap
    data={indicateurs_dpt}
    code=dpt value=naissances
    legendTitle="naissances"
    title="Naissances recensées"
    fmt={(v) => Number(v).toLocaleString('fr-FR', {maximumFractionDigits: 0})}
/>
<FranceMap
    data={indicateurs_dpt}
    code=dpt value=part_rares
    legendTitle="part"
    title="Part des enfants au prénom « rare » localement"
    subtitle="Prénoms non publiés au niveau départemental (secret statistique) : un indicateur d'originalité"
    fmt={(v) => (100 * v).toLocaleString('fr-FR', {maximumFractionDigits: 1}) + ' %'}
/>
</Grid>
