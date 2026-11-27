#!/usr/bin/env python3
"""Writes chronology.json: the outside data that the Chronology needs and the server does not give.

Usage: python3 make_chronology.py
It reads specimen.json and needs network access to the Wikidata query service.
"""

import json
import re
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
AGENT = "KlassikSpecimen/0.1 (https://github.com/whnr/klassik)"
CHOPIN = "Q1268"


def sparql(query):
    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": query})
    request = urllib.request.Request(url, headers={"Accept": "application/sparql-results+json", "User-Agent": AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)["results"]["bindings"]


def value(row, key):
    return row[key]["value"] if key in row else None


def year(row, key):
    v = value(row, key)
    return int(v) if v else None


def composers(names):
    """Life dates and work period start, matched on the English label of a composer item."""
    labels = " ".join(json.dumps(n) + "@en" for n in names)
    rows = sparql(f"""
        SELECT ?name ?item (MIN(YEAR(?born)) AS ?b) (MIN(YEAR(?died)) AS ?d) (MIN(YEAR(?active)) AS ?a) WHERE {{
          VALUES ?name {{ {labels} }}
          ?item rdfs:label ?name; wdt:P106 wd:Q36834; wdt:P569 ?born.
          OPTIONAL {{ ?item wdt:P570 ?died }}
          OPTIONAL {{ ?item wdt:P2031 ?active }}
        }} GROUP BY ?name ?item""")
    out = {}
    for row in rows:
        name = value(row, "name")
        # A label can name several composers; the one with work period data or the earliest item wins.
        entry = {
            "wikidata": row["item"]["value"].rsplit("/", 1)[-1],
            "born": year(row, "b"),
            "died": year(row, "d"),
            "activeFrom": year(row, "a"),
        }
        if name not in out or (entry["activeFrom"] and not out[name]["activeFrom"]):
            out[name] = entry
    return out


def catalogue_keys(title):
    """Keys that identify a Chopin work across title styles: opus and number, or a KK code."""
    keys = []
    kk = re.search(r"KK\s*([IVX]+[ab]?/\d+)", title)
    if kk:
        keys.append(("KK", kk.group(1)))
    op = re.search(r"Op\.\s*(?:posth\.\s*)?(\d+)(?:,?\s*No\.\s*(\d+))?", title, re.I)
    if op:
        keys.append((op.group(1), op.group(2)))
        lead = re.match(r"\D*?\bno\.\s*(\d+)", title, re.I)
        if not op.group(2) and lead:
            keys.append((op.group(1), lead.group(1)))
    return keys


def chopin_years():
    rows = sparql(f"""
        SELECT ?w ?wLabel (MIN(YEAR(?inc)) AS ?y) (GROUP_CONCAT(DISTINCT ?code; separator="|") AS ?codes) WHERE {{
          ?w wdt:P86 wd:{CHOPIN}; wdt:P571 ?inc.
          OPTIONAL {{ ?w wdt:P528 ?code }}
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }} GROUP BY ?w ?wLabel""")
    found = {}
    for row in rows:
        title = (
            row["wLabel"]["value"]
            + " "
            + " ".join(f"KK {c[3:]}" for c in (value(row, "codes") or "").split("|") if c.startswith("KK "))
        )
        for key in catalogue_keys(title):
            found.setdefault(key, set()).add(int(row["y"]["value"]))
    return {key: min(years) for key, years in found.items() if len(years) == 1}


def mbid_years(ids):
    values = " ".join(json.dumps(i) for i in ids)
    rows = sparql(f"""
        SELECT ?mb (MIN(YEAR(?inc)) AS ?y) WHERE {{
          VALUES ?mb {{ {values} }}
          ?w wdt:P435 ?mb; wdt:P571 ?inc.
        }} GROUP BY ?mb""")
    return {value(r, "mb"): year(r, "y") for r in rows}


def main():
    data = json.loads((HERE / "specimen.json").read_text())
    works = {}
    names = set()
    for album in data["albums"]:
        for song in album["song"]:
            names |= {c["artist"]["name"] for c in song.get("contributors", []) if c["role"] == "composer"}
            for work in song.get("works") or []:
                works[(song.get("displayComposer"), work["name"])] = work.get("musicBrainzId")
    by_mbid = mbid_years([m for m in works.values() if m])
    chopin = chopin_years()
    years = {}
    for (composer, name), mbid in sorted(works.items(), key=lambda kv: (str(kv[0][0]), kv[0][1])):
        y = by_mbid.get(mbid) if mbid else None
        if y is None and composer == "Frédéric Chopin":
            y = next((chopin[k] for k in catalogue_keys(name) if k in chopin), None)
        years.setdefault(composer, {})[name] = y
    out = {
        "about": "Outside data for the Chronology specimen, from Wikidata (CC0). Composer: P569, P570, P2031. "
        "Work: P571 through the MusicBrainz work ID (P435), or for Chopin through the catalogue number. "
        "null: no date found. Regenerate with make_chronology.py.",
        "composers": composers(sorted(names)),
        "workYears": years,
    }
    (HERE / "chronology.json").write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n")
    dated = sum(y is not None for ws in years.values() for y in ws.values())
    total = sum(len(ws) for ws in years.values())
    print(f"chronology.json: {len(out['composers'])} of {len(names)} composers, {dated} of {total} works dated")


if __name__ == "__main__":
    main()
