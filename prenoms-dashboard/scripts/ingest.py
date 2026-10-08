#!/usr/bin/env python3
"""
Ingestion du « Fichier des prénoms » de l'INSEE (data.gouv.fr) vers Parquet.

Étapes :
  1. retrouve les ressources (fichier départemental + fichier national) via l'API data.gouv.fr ;
  2. télécharge les archives dans data/raw/ ;
  3. normalise le schéma avec DuckDB (les éditions INSEE n'ont pas toutes les mêmes colonnes) ;
  4. écrit des fichiers Parquet compressés (zstd) dans data/, lus ensuite par Evidence.

Usage :
  python3 scripts/ingest.py                      # découverte automatique sur data.gouv.fr
  python3 scripts/ingest.py --dpt-url URL [--nat-url URL]
  python3 scripts/ingest.py --dpt-file dpt2023.csv [--nat-file nat2023.csv]
  python3 scripts/ingest.py --demo               # jeu synthétique pour tester le tableau de bord hors-ligne
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import random
import re
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
RAW = DATA / "raw"
DEPARTEMENTS_CSV = Path(__file__).resolve().parent / "departements.csv"

API = "https://www.data.gouv.fr/api/1"
DATASET_SLUGS = [
    "fichier-des-prenoms-depuis-1900",
    "fichier-des-prenoms-1900-2023",
    "fichier-des-prenoms-1900-2022",
]
SEARCH_QUERY = "fichier des prénoms depuis 1900"

# Noms de colonnes rencontrés selon les éditions INSEE (2019 → 2025)
COLS = {
    "sexe": ["sexe", "sex", "genre"],
    "prenom": ["preusuel", "prenom", "prénom", "prenom_usuel"],
    "annee": ["annais", "annee", "année", "periode", "période", "annee_naissance", "time_period"],
    "dpt": ["dpt", "departement", "département", "dep", "code_departement", "geo", "geo_object", "geo_code"],
    "nombre": ["nombre", "valeur", "effectif", "nb", "obs_value", "nombre_naissances"],
    "niveau": ["niveau_geographique", "geo_level", "niveau"],
}


# --------------------------------------------------------------------------- découverte

def http_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "prenoms-dashboard/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def find_dataset() -> dict:
    for slug in DATASET_SLUGS:
        try:
            return http_json(f"{API}/datasets/{slug}/")
        except Exception:
            continue
    q = urllib.parse.quote(SEARCH_QUERY)
    res = http_json(f"{API}/datasets/?q={q}&page_size=10")
    for d in res.get("data", []):
        org = (d.get("organization") or {}).get("name", "")
        if "insee" in org.lower() or "Institut national" in org:
            return d
    raise SystemExit("Jeu de données INSEE « Fichier des prénoms » introuvable sur data.gouv.fr")


def classify(resource: dict) -> str | None:
    text = f"{resource.get('title', '')} {resource.get('url', '')}".lower()
    fmt = (resource.get("format") or "").lower()
    if fmt and fmt not in ("csv", "zip", "parquet", "dbf", "txt") and not text.endswith((".zip", ".csv", ".parquet")):
        return None
    if "doc" in text and "dpt" not in text and "nat" not in text:
        return None
    if re.search(r"dpt|d[ée]part", text):
        return "dpt"
    if re.search(r"nat|national|france", text):
        return "nat"
    return None


def pick_resources(dataset: dict) -> dict[str, dict]:
    """Retient pour chaque niveau la ressource la plus récente, en privilégiant CSV/Parquet zippé."""
    pref = {"parquet": 3, "csv": 2, "zip": 2, "txt": 1, "dbf": 0}
    best: dict[str, dict] = {}
    for r in dataset.get("resources", []):
        kind = classify(r)
        if not kind:
            continue
        score = (r.get("last_modified") or r.get("created_at") or "", pref.get((r.get("format") or "").lower(), 1))
        if kind not in best or score > best[kind]["_score"]:
            best[kind] = {**r, "_score": score}
    return best


def download(url: str, dest_dir: Path) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    name = url.rstrip("/").split("/")[-1].split("?")[0] or "download"
    dest = dest_dir / name
    if dest.exists() and dest.stat().st_size > 0:
        print(f"  ↺ déjà téléchargé : {dest.name}")
        return dest
    print(f"  ↓ {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "prenoms-dashboard/1.0"})
    with urllib.request.urlopen(req, timeout=600) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f)
    print(f"    {dest.stat().st_size / 1e6:.1f} Mo")
    return dest


def unpack(path: Path) -> Path:
    """Renvoie le fichier de données (csv/parquet) — extrait l'archive si besoin."""
    if not zipfile.is_zipfile(path):
        return path
    out = path.parent / (path.stem + "_unzip")
    with zipfile.ZipFile(path) as z:
        members = [m for m in z.namelist() if m.lower().endswith((".csv", ".parquet", ".txt")) and not m.startswith("__MACOSX")]
        if not members:
            raise SystemExit(f"Aucun fichier de données dans {path.name}")
        member = max(members, key=lambda m: z.getinfo(m).file_size)
        target = out / Path(member).name
        if not target.exists():
            out.mkdir(exist_ok=True)
            with z.open(member) as src, open(target, "wb") as dst:
                shutil.copyfileobj(src, dst)
    return target


# --------------------------------------------------------------------------- normalisation

def pick(cols: list[str], role: str) -> str | None:
    lower = {c.lower().strip(): c for c in cols}
    for cand in COLS[role]:
        if cand in lower:
            return lower[cand]
    return None


def read_raw(con: duckdb.DuckDBPyConnection, path: Path, view: str) -> None:
    p = str(path).replace("'", "''")
    if path.suffix.lower() == ".parquet":
        con.execute(f"create or replace view {view} as select * from read_parquet('{p}')")
    else:
        con.execute(
            f"create or replace view {view} as select * from read_csv('{p}', all_varchar=true, header=true, "
            f"auto_detect=true, sample_size=-1)"
        )


def normalize(con: duckdb.DuckDBPyConnection, src_view: str, out_table: str, with_dpt: bool) -> None:
    cols = [r[0] for r in con.execute(f"describe {src_view}").fetchall()]
    m = {role: pick(cols, role) for role in COLS}
    needed = ["sexe", "prenom", "annee", "nombre"] + (["dpt"] if with_dpt else [])
    missing = [k for k in needed if not m[k]]
    if missing:
        raise SystemExit(f"Colonnes introuvables {missing} dans {cols}")
    print(f"  colonnes détectées : { {k: v for k, v in m.items() if v} }")

    q = lambda c: '"' + c.replace('"', '""') + '"'
    where = ""
    if m["niveau"] and with_dpt:
        where = f"where lower(cast({q(m['niveau'])} as varchar)) like '%dep%'"
    elif m["niveau"]:
        where = f"where lower(cast({q(m['niveau'])} as varchar)) similar to '.*(fr|nat|pays).*'"

    dpt_expr = ""
    if with_dpt:
        raw = f"upper(trim(cast({q(m['dpt'])} as varchar)))"
        dpt_expr = f""",
        case
          when regexp_full_match({raw}, '.*\\b(2A|2B)$') then regexp_extract({raw}, '(2A|2B)$')
          when regexp_matches({raw}, '97[0-9]$') then regexp_extract({raw}, '(97[0-9])$')
          when regexp_matches({raw}, '[0-9]{{1,2}}$') then lpad(regexp_extract({raw}, '([0-9]{{1,2}})$'), 2, '0')
          else null end as dpt"""

    con.execute(f"""
    create or replace table {out_table} as
    with src as (
      select
        case upper(trim(cast({q(m['sexe'])} as varchar)))
          when '1' then 'M' when 'M' then 'M' when 'H' then 'M' when 'G' then 'M' when 'MASCULIN' then 'M'
          when '2' then 'F' when 'F' then 'F' when 'FEMININ' then 'F' when 'FÉMININ' then 'F'
        end as sexe,
        upper(trim(cast({q(m['prenom'])} as varchar))) as prenom,
        try_cast(regexp_extract(cast({q(m['annee'])} as varchar), '([12][0-9]{{3}})') as smallint) as annee,
        try_cast(replace(cast({q(m['nombre'])} as varchar), ' ', '') as integer) as nombre
        {dpt_expr}
      from {src_view}
      {where}
    )
    select sexe, prenom, annee, {'dpt, ' if with_dpt else ''}sum(nombre)::integer as nombre
    from src
    where sexe is not null and prenom is not null and prenom <> '' and nombre > 0
    group by all
    """)
    n = con.execute(f"select count(*), sum(nombre) from {out_table}").fetchone()
    print(f"  → {out_table} : {n[0]:,} lignes, {n[1]:,} naissances".replace(",", " "))


def label(prenom: str) -> str:
    if prenom.startswith("_"):
        return "Prénoms rares"
    return re.sub(r"(^|[-' ])(\w)", lambda mm: mm.group(1) + mm.group(2).upper(), prenom.lower())


# --------------------------------------------------------------------------- démo

def make_demo(path: Path, seed: int = 42) -> None:
    """Jeu synthétique au format INSEE dpt (sexe;preusuel;annais;dpt;nombre). Données FICTIVES."""
    rng = random.Random(seed)
    names = {
        1: "JEAN PIERRE MICHEL ANDRÉ PHILIPPE RENÉ LOUIS ALAIN JACQUES BERNARD MARCEL DANIEL ROGER ROBERT PAUL "
           "CHRISTIAN HENRI GEORGES NICOLAS FRANÇOIS PATRICK GÉRARD CHRISTOPHE JOSEPH CLAUDE THOMAS JULIEN "
           "SÉBASTIEN DAVID FRÉDÉRIC MAXIME LUCAS ALEXANDRE ANTOINE LÉO GABRIEL RAPHAËL ARTHUR LOUIS HUGO "
           "NATHAN ENZO THÉO MATHIS KEVIN ROMAIN YANN ERWAN MOHAMED ADAM NOAH JULES MAËL SACHA EDEN AARON "
           "JEAN-PIERRE JEAN-CLAUDE JEAN-LUC GILLES OLIVIER STÉPHANE ÉRIC PASCAL THIERRY LAURENT FABRICE",
        2: "MARIE JEANNE FRANÇOISE MONIQUE CATHERINE NATHALIE ISABELLE JACQUELINE ANNE SYLVIE MARTINE "
           "MADELEINE NICOLE SUZANNE HÉLÈNE CHRISTINE MARGUERITE DENISE LOUISE CHRISTIANE YVETTE GERMAINE "
           "SANDRINE STÉPHANIE CÉLINE JULIE AURÉLIE LAURA CAMILLE MANON EMMA LÉA CHLOÉ INÈS JADE LOUISE ALICE "
           "LINA ROSE AMBRE MIA ANNA ZOÉ LÉNA SARAH OCÉANE MARINE PAULINE ÉMILIE NOLWENN MAËLLE ANAÏS "
           "MARIE-THÉRÈSE MARIE-CLAUDE BRIGITTE VALÉRIE VÉRONIQUE CORINNE DOMINIQUE CLAUDE CAMILLE",
    }
    dpts = [l.split(",")[0] for l in DEPARTEMENTS_CSV.read_text(encoding="utf-8").splitlines()[1:]]
    weight = {d: rng.uniform(0.3, 3.0) * (6 if d in ("75", "59", "13", "69", "93", "92") else 1) for d in dpts}
    tw = sum(weight.values())
    regional = {"YANN": ["29", "22", "56", "35"], "ERWAN": ["29", "22", "56"], "NOLWENN": ["29", "22", "56", "35"],
                "MAËLLE": ["29", "56", "35", "44"], "MOHAMED": ["93", "13", "69", "95", "59"], "ADAM": ["93", "95", "13"]}
    first_year, last_year = 1900, 2024

    def births(y):  # baby-boom approximatif
        base = 850_000 + 150_000 * math.exp(-((y - 1955) / 18) ** 2) - 250_000 * math.exp(-((y - 1916) / 2.5) ** 2)
        return base * 0.97

    with open(path, "w", encoding="utf-8") as f:
        f.write("sexe;preusuel;annais;dpt;nombre\n")
        for sexe, lst in names.items():
            for name in dict.fromkeys(lst.split()):
                peak = rng.randint(1905, 2022)
                width = rng.uniform(8, 25)
                amp = rng.uniform(0.004, 0.03)
                if name in ("MARIE", "JEAN"):
                    peak, width, amp = 1910, 40, 0.09
                for y in range(first_year, last_year + 1):
                    share = amp * math.exp(-((y - peak) / width) ** 2)
                    tot = births(y) / 2 * share
                    if tot < 20:
                        continue
                    for d in dpts:
                        w = weight[d] / tw * (8 if d in regional.get(name, []) else 1)
                        n = int(rng.gauss(tot * w, math.sqrt(tot * w) + 0.5))
                        if n >= 3:
                            f.write(f"{sexe};{name};{y};{d};{n}\n")
                        elif n > 0:
                            f.write(f"{sexe};{name};XXXX;XX;{n}\n")
            for y in range(first_year, last_year + 1):
                for d in dpts:
                    f.write(f"{sexe};_PRENOMS_RARES;{y};{d};{int(births(y) / 2 * 0.25 * weight[d] / tw)}\n")


# --------------------------------------------------------------------------- main

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dpt-url"), ap.add_argument("--nat-url")
    ap.add_argument("--dpt-file", type=Path), ap.add_argument("--nat-file", type=Path)
    ap.add_argument("--demo", action="store_true", help="génère des données fictives (test hors-ligne)")
    args = ap.parse_args()

    DATA.mkdir(exist_ok=True)
    RAW.mkdir(exist_ok=True)
    meta = {"genere_le": dt.datetime.now().isoformat(timespec="seconds"), "demo": args.demo,
            "source": "INSEE — Fichier des prénoms (data.gouv.fr)", "url_dpt": None, "url_nat": None, "edition": None}

    print("1/4  Localisation des fichiers")
    dpt_path, nat_path = args.dpt_file, args.nat_file
    if args.demo:
        dpt_path = RAW / "demo_dpt.csv"
        make_demo(dpt_path)
        meta["source"] = "DONNÉES FICTIVES (mode démo)"
    elif not dpt_path:
        dpt_url, nat_url = args.dpt_url, args.nat_url
        if not dpt_url:
            ds = find_dataset()
            print(f"  jeu de données : {ds.get('title')} ({ds.get('page')})")
            res = pick_resources(ds)
            if "dpt" not in res:
                raise SystemExit("Ressource départementale introuvable — utilisez --dpt-url")
            dpt_url = res["dpt"]["url"]
            nat_url = nat_url or res.get("nat", {}).get("url")
            meta["edition"] = res["dpt"].get("title")
        meta["url_dpt"], meta["url_nat"] = dpt_url, nat_url
        print("2/4  Téléchargement")
        dpt_path = download(dpt_url, RAW)
        if nat_url:
            nat_path = download(nat_url, RAW)

    con = duckdb.connect()
    con.execute("set preserve_insertion_order = false")

    print("3/4  Normalisation (DuckDB)")
    read_raw(con, unpack(dpt_path), "raw_dpt")
    normalize(con, "raw_dpt", "dpt", with_dpt=True)
    if nat_path:
        read_raw(con, unpack(nat_path), "raw_nat")
        normalize(con, "raw_nat", "nat", with_dpt=False)
    else:
        print("  pas de fichier national : agrégation du fichier départemental")
        con.execute("create table nat as select sexe, prenom, annee, sum(nombre)::integer as nombre from dpt group by all")

    # libellés lisibles (« JEAN-PIERRE » → « Jean-Pierre »)
    prenoms = {r[0] for r in con.execute("select distinct prenom from nat union select distinct prenom from dpt").fetchall()}
    con.execute("create table labels(prenom varchar, libelle varchar)")
    con.executemany("insert into labels values (?, ?)", [(p, label(p)) for p in prenoms])

    con.execute(f"create table departements as select * from read_csv('{DEPARTEMENTS_CSV}', all_varchar=true)")

    print("4/4  Écriture Parquet")
    out = {
        "prenoms_departements": "select d.sexe, d.prenom, l.libelle, d.annee, d.dpt, d.nombre from dpt d join labels l using (prenom) order by d.prenom, d.annee, d.dpt",
        "prenoms_france": "select n.sexe, n.prenom, l.libelle, n.annee, n.nombre from nat n join labels l using (prenom) order by n.prenom, n.annee",
        "departements": "select * from departements",
    }
    for name, sql in out.items():
        target = DATA / f"{name}.parquet"
        con.execute(f"copy ({sql}) to '{target}' (format parquet, compression zstd, row_group_size 250000)")
        print(f"  ✓ {target.relative_to(ROOT)} ({target.stat().st_size / 1e6:.1f} Mo)")
    yr = con.execute("select min(annee), max(annee) from nat").fetchone()
    meta["annee_min"], meta["annee_max"] = yr
    con.execute("create table meta as select * from (select unnest(?::json[]) as j)", [[json.dumps(meta)]])
    con.execute(f"""copy (select j->>'source' as source, j->>'edition' as edition, j->>'url_dpt' as url_dpt,
        j->>'url_nat' as url_nat, (j->>'demo')::boolean as demo, j->>'genere_le' as genere_le,
        (j->>'annee_min')::int as annee_min, (j->>'annee_max')::int as annee_max from meta)
        to '{DATA / 'meta.parquet'}' (format parquet)""")
    print("Terminé. Lancez maintenant : npm run sources && npm run dev")


if __name__ == "__main__":
    import urllib.parse  # noqa: F401  (utilisé par find_dataset)
    main()
