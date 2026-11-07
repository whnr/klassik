#!/usr/bin/env python3
"""Writes people.json: Wikidata facts, a Commons picture and a Wikipedia lead for each composer and performer.

Usage: python3 make_people.py
It reads specimen.json and chronology.json and needs network access.
Composers come from their item in chronology.json. Performers are found as ADR 0019 says:
a search with haswbstatement:P434, else without it.
"""

import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from html import unescape
from pathlib import Path

HERE = Path(__file__).resolve().parent
AGENT = "KlassikSpecimen/0.1 (https://github.com/whnr/klassik)"


def get(url, **params):
    request = urllib.request.Request(url + "?" + urllib.parse.urlencode(params), headers={"User-Agent": AGENT})
    for wait in (1, 5, 15, 45, 90):
        time.sleep(0.5)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Wikimedia answers 429 when a client asks too fast; wait and ask again.
            if error.code != 429:
                raise
            time.sleep(wait)
    raise RuntimeError(f"still rate limited: {url}")


def wikidata(**params):
    return get("https://www.wikidata.org/w/api.php", format="json", **params)


def find(name):
    for query in (f'"{name}" haswbstatement:P434', f'"{name}"'):
        hits = wikidata(action="query", list="search", srsearch=query, srlimit=1)["query"]["search"]
        if hits:
            return hits[0]["title"]
    return None


def year(claims, prop):
    for c in claims.get(prop, []):
        v = c["mainsnak"].get("datavalue", {}).get("value", {})
        match = re.match(r"[+-](\d{4})", v.get("time", ""))
        if match:
            return int(match.group(1))
    return None


def plain(html):
    return re.sub(r"\s+", " ", unescape(re.sub(r"<[^>]+>", "", html or ""))).strip()


def picture(file):
    info = get("https://commons.wikimedia.org/w/api.php", action="query", format="json", prop="imageinfo",
               titles="File:" + file, iiprop="url|extmetadata", iiurlwidth=1280)
    page = next(iter(info["query"]["pages"].values()))
    if "imageinfo" not in page:
        return None
    ii = page["imageinfo"][0]
    meta = ii.get("extmetadata", {})
    return {"url": ii.get("thumburl") or ii["url"], "page": ii["descriptionurl"],
            "author": plain(meta.get("Artist", {}).get("value")) or "Unknown",
            "licence": plain(meta.get("LicenseShortName", {}).get("value")) or "See file page"}


def lead(title):
    pages = get("https://en.wikipedia.org/w/api.php", action="query", format="json", prop="extracts",
                exintro=1, explaintext=1, titles=title)["query"]["pages"]
    return next(iter(pages.values())).get("extract", "").strip() or None


def person(qid):
    entity = wikidata(action="wbgetentities", ids=qid, props="claims|descriptions|sitelinks", languages="en",
                      sitefilter="enwiki")["entities"][qid]
    claims = entity.get("claims", {})
    file = claims.get("P18", [{}])[0].get("mainsnak", {}).get("datavalue", {}).get("value")
    wiki = entity.get("sitelinks", {}).get("enwiki", {}).get("title")
    return {
        "wikidata": qid,
        "description": entity.get("descriptions", {}).get("en", {}).get("value"),
        "born": year(claims, "P569"), "died": year(claims, "P570"),
        "picture": picture(file) if file else None,
        "bio": lead(wiki) if wiki else None,
        "wikipedia": f"https://en.wikipedia.org/wiki/{urllib.parse.quote(wiki.replace(' ', '_'))}" if wiki else None,
    }


def main():
    data = json.loads((HERE / "specimen.json").read_text())
    chronology = json.loads((HERE / "chronology.json").read_text())
    composers = chronology["composers"]
    performers = set()
    for album in data["albums"]:
        for song in album["song"]:
            for c in song.get("contributors", []):
                if c["role"] in ("conductor", "performer"):
                    performers.add(c["artist"]["name"])
    out = {}
    for name, facts in sorted(composers.items()):
        out[name] = dict(person(facts["wikidata"]), kind="composer")
    for name in sorted(performers - set(out)):
        qid = find(name)
        out[name] = dict(person(qid), kind="performer") if qid else {"kind": "performer", "wikidata": None}
        print(name, qid)
    (HERE / "people.json").write_text(json.dumps(
        {"about": "Wikidata (CC0), Commons pictures with their credits, Wikipedia leads (CC BY-SA 4.0). "
                  "Regenerate with make_people.py.", "people": out}, ensure_ascii=False, indent=1) + "\n")
    found = sum(1 for p in out.values() if p.get("picture"))
    print(f"people.json: {len(out)} people, {found} with a picture")


if __name__ == "__main__":
    main()
