#!/usr/bin/env python3
"""Probe Wikidata, Wikipedia and Commons with composer names as a weak library tags them.

Usage: python3 -I probe.py
Writes nothing. Downloads no image. Counts every HTTP request.
"""
import json
import time
import urllib.parse
import urllib.request

UA = "KlassikResearch/0.1 (https://github.com/florian-wehner/klassik; florian@whnr.de) python-urllib"
COMPOSER = "Q36834"
WD = "https://www.wikidata.org/w/api.php"
requests = 0


def get(url, params=None):
    global requests
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "identity"})
    requests += 1
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r), r.headers


def wbsearch(name, lang="en"):
    """Strategy A: label and alias search, then filter by occupation."""
    d, _ = get(WD, dict(action="wbsearchentities", search=name, language=lang,
                        type="item", limit=10, format="json"))
    ids = [x["id"] for x in d["search"]]
    if not ids:
        return []
    e, _ = get(WD, dict(action="wbgetentities", ids="|".join(ids), props="claims",
                        format="json"))
    out = []
    for i in ids:
        occ = {c["mainsnak"]["datavalue"]["value"]["id"]
               for c in e["entities"][i].get("claims", {}).get("P106", [])
               if "datavalue" in c["mainsnak"]}
        if COMPOSER in occ:
            out.append(i)
    return out


def cirrus(name):
    """Strategy B: full-text search with the occupation filter in one request."""
    d, _ = get(WD, dict(action="query", list="search", srsearch=f"{name} haswbstatement:P106={COMPOSER}",
                        srlimit=5, format="json"))
    return [x["title"] for x in d["query"]["search"]]


def claim_time(claims, prop):
    for c in claims.get(prop, []):
        v = c["mainsnak"].get("datavalue", {}).get("value")
        if v:
            return v["time"][:11], v["precision"]
    return None


def entity(qid):
    d, _ = get(WD, dict(action="wbgetentities", ids=qid, format="json",
                        props="labels|descriptions|claims|sitelinks",
                        languages="en|de", sitefilter="enwiki|dewiki"))
    return d["entities"][qid]


def summary(lang, title):
    d, _ = get(f"https://{lang}.wikipedia.org/api/rest_v1/page/summary/"
               + urllib.parse.quote(title.replace(" ", "_"), safe=""))
    return d


def commons_license(filename):
    d, _ = get("https://commons.wikimedia.org/w/api.php",
               dict(action="query", titles="File:" + filename, prop="imageinfo",
                    iiprop="extmetadata|size|url", iiextmetadatafilter=
                    "LicenseShortName|License|UsageTerms|Artist|Credit|AttributionRequired|Copyrighted",
                    format="json"))
    p = next(iter(d["query"]["pages"].values()))
    ii = p["imageinfo"][0]
    m = {k: v["value"] for k, v in ii["extmetadata"].items()}
    return ii["width"], ii["height"], m


def sparql_batch(qids):
    """One request for dates, description, image file and article links of many items."""
    global requests
    values = " ".join("wd:" + q for q in qids)
    q = ("SELECT ?p ?pLabel ?pDescription ?b ?d ?img ?en ?de WHERE { VALUES ?p { " + values + " } "
         "OPTIONAL{?p wdt:P569 ?b} OPTIONAL{?p wdt:P570 ?d} OPTIONAL{?p wdt:P18 ?img} "
         "OPTIONAL{?en schema:about ?p; schema:isPartOf <https://en.wikipedia.org/>} "
         "OPTIONAL{?de schema:about ?p; schema:isPartOf <https://de.wikipedia.org/>} "
         'SERVICE wikibase:label { bd:serviceParam wikibase:language "en,de". } }')
    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": q})
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/sparql-results+json"})
    requests += 1
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["results"]["bindings"]


def main():
    variants = ["Bach", "J.S. Bach", "Johann Sebastian Bach", "Bach, Johann Sebastian",
                "Tchaikovsky", "Tschaikowsky", "Chopin, Frédéric", "Chopin", "Dvorak",
                "Dvořák", "Mozart", "W.A. Mozart", "Beethoven, Ludwig van", "Rachmaninov",
                "Rachmaninoff", "Mussorgsky", "Moussorgski", "Scarlatti", "Strauss",
                "Brahms", "Schönberg", "Schoenberg", "Debussy, Claude", "Händel",
                "Handel", "Sibelius", "Pärt", "Arvo Part"]
    print("name | A first composer hit | B first hit | agree")
    for v in variants:
        a = wbsearch(v)
        time.sleep(0.2)
        b = cirrus(v)
        time.sleep(0.2)
        print(f"{v!r} | A={a[:3]} | B={b[:3]} | top1 same={bool(a and b and a[0]==b[0])}")
    print("--- entity facts for Q1339, Q7315, Q7298")
    for q in ["Q1339", "Q7315", "Q7298", "Q76428"]:
        e = entity(q)
        cl = e["claims"]
        p18 = [c["mainsnak"]["datavalue"]["value"] for c in cl.get("P18", [])
               if "datavalue" in c["mainsnak"]]
        print(q, e["labels"].get("en", {}).get("value"), "born", claim_time(cl, "P569"),
              "died", claim_time(cl, "P570"), "P18", p18[:1],
              "sitelinks", {k: v["title"] for k, v in e.get("sitelinks", {}).items()})
        if p18:
            print("   commons", commons_license(p18[0]))
        sl = e.get("sitelinks", {}).get("enwiki")
        if sl:
            s = summary("en", sl["title"])
            print("   summary", s.get("description"), "|", s.get("extract", "")[:120],
                  "| thumb", s.get("thumbnail", {}).get("source"))
    print("--- one SPARQL request for the same items")
    for r in sparql_batch(["Q1339", "Q7315", "Q7298", "Q189534"]):
        print({k: v["value"][:70] for k, v in r.items()})
    print("--- names that are not composers")
    for v in ["Anonymous", "Traditional", "Various Artists", "Unknown"]:
        print(v, cirrus(v)[:3])
    print("total requests", requests)


if __name__ == "__main__":
    main()
