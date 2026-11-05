#!/usr/bin/env python3
"""Probe Wikidata and Commons with performer names as a weak library tags them.

Usage: python3 -I probe.py
Writes nothing. Downloads no image. Counts every HTTP request.
The names are public, well-known classical performers. No library was read.
"""
import json
import re
import time
import unicodedata
import urllib.parse
import urllib.request
from collections import Counter

UA = "KlassikResearch/0.1 (https://github.com/florian-wehner/klassik; florian@whnr.de) python-urllib"
WD = "https://www.wikidata.org/w/api.php"
requests = 0

# Right item for each performer. Each Q-number was checked by its English label.
TRUTH = {
    "karajan": "Q154895", "abbado": "Q151608", "rattle": "Q157814", "bernstein": "Q152505",
    "petrenko_k": "Q478275", "petrenko_v": "Q2060404", "harnoncourt": "Q78526",
    "kleiber_c": "Q160706", "kleiber_e": "Q78527", "gardiner": "Q160325", "currentzis": "Q536185",
    "davis": "Q366624", "levine": "Q336388", "salonen": "Q314587", "marriner": "Q318636",
    "jansons": "Q158340", "hogwood": "Q435198", "herreweghe": "Q168039", "savall": "Q317182",
    "koopman": "Q445121", "leonhardt": "Q51584",
    "gould": "Q216924", "m_gould": "Q1352656", "argerich": "Q156810", "mutter": "Q3374",
    "hahn": "Q235406", "yoyoma": "Q234891", "dupre": "Q228888", "rostropovich": "Q152043",
    "richter": "Q124890", "langlang": "Q155713", "levit": "Q100759", "trifonov": "Q2635946",
    "perlman": "Q215905", "schiff": "Q427319", "maisky": "Q381759", "ax": "Q505563",
    "ashkenazy": "Q157785", "bezuidenhout": "Q2249018", "volodos": "Q631344",
    "meyer": "Q263349", "gabetta": "Q509148",
    "callas": "Q128297", "fd": "Q77060", "bartoli": "Q18828", "kaufmann": "Q62358",
    "netrebko": "Q78516", "schwarzkopf": "Q57288", "pavarotti": "Q37615",
    "jaroussky": "Q441502", "kirkby": "Q242430", "scholl": "Q57439",
    "bpo": "Q152222", "vpo": "Q154685", "lso": "Q155805", "rco": "Q827768",
    "gewandhaus": "Q156515", "dresden": "Q584017", "brso": "Q636159", "coe": "Q661670",
    "mco": "Q573902", "asmf": "Q337362", "orr": "Q2616019", "ebs": "Q1342808",
    "fbo": "Q454974", "cmw": "Q372863", "giardino": "Q700172", "laf": "Q1752532",
    "hesperion": "Q1615681", "srso": "Q2066271", "aam": "Q337310",
    "monteverdi": "Q372854", "rias": "Q320444", "sixteen": "Q3067073", "tallis": "Q536565",
    "thomaner": "Q699313", "wsk": "Q266508", "brc": "Q881144", "cvg": "Q1109305",
    "emerson": "Q681006", "abq": "Q389156", "hagen": "Q696597", "ebene": "Q3413743",
    "beauxarts": "Q813472", "kronos": "Q1126131",
}
ENSEMBLES = {"bpo", "vpo", "lso", "rco", "gewandhaus", "dresden", "brso", "coe", "mco", "asmf",
             "orr", "ebs", "fbo", "cmw", "giardino", "laf", "hesperion", "srso", "aam",
             "monteverdi", "rias", "sixteen", "tallis", "thomaner", "wsk", "brc", "cvg",
             "emerson", "abq", "hagen", "ebene", "beauxarts", "kronos"}

# One tag value each, as tags in other libraries spell them. A list means: any of these is right.
VARIANTS = [
    ("Herbert von Karajan", "karajan"), ("Karajan", "karajan"), ("Karajan, Herbert von", "karajan"),
    ("Claudio Abbado", "abbado"), ("Abbado", "abbado"), ("Sir Simon Rattle", "rattle"),
    ("Simon Rattle", "rattle"), ("Leonard Bernstein", "bernstein"), ("Bernstein", "bernstein"),
    ("Kirill Petrenko", "petrenko_k"), ("Nikolaus Harnoncourt", "harnoncourt"),
    ("Harnoncourt", "harnoncourt"), ("Carlos Kleiber", "kleiber_c"),
    ("Sir John Eliot Gardiner", "gardiner"), ("Teodor Currentzis", "currentzis"),
    ("Sir Colin Davis", "davis"), ("Esa-Pekka Salonen", "salonen"),
    ("Neville Marriner", "marriner"), ("Mariss Jansons", "jansons"),
    ("Philippe Herreweghe", "herreweghe"), ("Jordi Savall", "savall"), ("Ton Koopman", "koopman"),
    ("Glenn Gould", "gould"), ("Martha Argerich", "argerich"), ("Argerich", "argerich"),
    ("Anne-Sophie Mutter", "mutter"), ("Anne Sophie Mutter", "mutter"), ("Hilary Hahn", "hahn"),
    ("Yo-Yo Ma", "yoyoma"), ("Yo Yo Ma", "yoyoma"), ("Jacqueline du Pre", "dupre"),
    ("Mstislav Rostropovich", "rostropovich"), ("Rostropowitsch", "rostropovich"),
    ("Sviatoslav Richter", "richter"), ("Swjatoslaw Richter", "richter"), ("Lang Lang", "langlang"),
    ("Igor Levit", "levit"), ("Daniil Trifonov", "trifonov"), ("Itzhak Perlman", "perlman"),
    ("Andras Schiff", "schiff"), ("Sir András Schiff", "schiff"), ("Mischa Maisky", "maisky"),
    ("Vladimir Ashkenazy", "ashkenazy"), ("Arcadi Volodos", "volodos"),
    ("Sabine Meyer", "meyer"), ("Sol Gabetta", "gabetta"),
    ("Maria Callas", "callas"), ("Callas", "callas"), ("Dietrich Fischer-Dieskau", "fd"),
    ("Fischer-Dieskau", "fd"), ("Cecilia Bartoli", "bartoli"), ("Jonas Kaufmann", "kaufmann"),
    ("Anna Netrebko", "netrebko"), ("Elisabeth Schwarzkopf", "schwarzkopf"),
    ("Pavarotti", "pavarotti"), ("Philippe Jaroussky", "jaroussky"), ("Emma Kirkby", "kirkby"),
    ("Andreas Scholl", "scholl"),
    ("Berliner Philharmoniker", "bpo"), ("Berlin Philharmonic Orchestra", "bpo"),
    ("Wiener Philharmoniker", "vpo"), ("Vienna Philharmonic Orchestra", "vpo"),
    ("London Symphony Orchestra", "lso"), ("Concertgebouw Orchestra", "rco"),
    ("Koninklijk Concertgebouworkest", "rco"), ("Gewandhausorchester Leipzig", "gewandhaus"),
    ("Staatskapelle Dresden", "dresden"), ("Symphonieorchester des Bayerischen Rundfunks", "brso"),
    ("Chamber Orchestra of Europe", "coe"), ("Mahler Chamber Orchestra", "mco"),
    ("Academy of St. Martin-in-the-Fields", "asmf"),
    ("Orchestre Révolutionnaire et Romantique", "orr"), ("English Baroque Soloists", "ebs"),
    ("Freiburger Barockorchester", "fbo"), ("Concentus Musicus Wien", "cmw"),
    ("Il Giardino Armonico", "giardino"), ("Les Arts Florissants", "laf"),
    ("Hesperion XXI", "hesperion"), ("Swedish Radio Symphony Orchestra", "srso"),
    ("The Academy of Ancient Music", "aam"),
    ("Monteverdi Choir", "monteverdi"), ("RIAS-Kammerchor", "rias"), ("The Sixteen", "sixteen"),
    ("The Tallis Scholars", "tallis"), ("Thomanerchor Leipzig", "thomaner"),
    ("Wiener Sängerknaben", "wsk"), ("Chor des Bayerischen Rundfunks", "brc"),
    ("Collegium Vocale Gent", "cvg"),
    ("Emerson String Quartet", "emerson"), ("Alban Berg Quartett", "abq"),
    ("Hagen Quartett", "hagen"), ("Quatuor Ebene", "ebene"), ("Beaux Arts Trio", "beauxarts"),
    ("Kronos Quartet", "kronos"),
]
# Surname tags that name two performers. Report the hit; neither is "wrong".
AMBIGUOUS = [("Kleiber", ["kleiber_c", "kleiber_e"]), ("Petrenko", ["petrenko_k", "petrenko_v"]),
             ("Gould", ["gould", "m_gould"])]

# Album-wide artist strings as one tag value, with the performers they name.
ALBUM_ARTISTS = [
    ("Berliner Philharmoniker, Herbert von Karajan", ["bpo", "karajan"]),
    ("Herbert von Karajan; Berliner Philharmoniker", ["karajan", "bpo"]),
    ("Karajan, Herbert von; Berliner Philharmoniker", ["karajan", "bpo"]),
    ("Martha Argerich, Claudio Abbado, Berliner Philharmoniker", ["argerich", "abbado", "bpo"]),
    ("Anne-Sophie Mutter / Wiener Philharmoniker / James Levine", ["mutter", "vpo", "levine"]),
    ("Glenn Gould & Leonard Bernstein", ["gould", "bernstein"]),
    ("London Symphony Orchestra & Sir Colin Davis", ["lso", "davis"]),
    ("Hilary Hahn, Esa-Pekka Salonen, Swedish Radio Symphony Orchestra", ["hahn", "salonen", "srso"]),
    ("Emerson String Quartet feat. Mstislav Rostropovich", ["emerson", "rostropovich"]),
    ("Yo-Yo Ma and Emanuel Ax", ["yoyoma", "ax"]),
    ("Monteverdi Choir, English Baroque Soloists, John Eliot Gardiner", ["monteverdi", "ebs", "gardiner"]),
    ("Freiburger Barockorchester & Kristian Bezuidenhout", ["fbo", "bezuidenhout"]),
    ("Concentus Musicus Wien; Nikolaus Harnoncourt", ["cmw", "harnoncourt"]),
    ("Orchestre Révolutionnaire et Romantique, John Eliot Gardiner", ["orr", "gardiner"]),
    ("Academy of St Martin in the Fields, Sir Neville Marriner", ["asmf", "marriner"]),
    ("Collegium Vocale Gent, Philippe Herreweghe", ["cvg", "herreweghe"]),
    ("Jordi Savall, Hespèrion XXI", ["savall", "hesperion"]),
    ("Chor und Symphonieorchester des Bayerischen Rundfunks, Mariss Jansons", ["brc", "brso", "jansons"]),
    ("Cecilia Bartoli & Il Giardino Armonico", ["bartoli", "giardino"]),
    ("Itzhak Perlman, Vladimir Ashkenazy", ["perlman", "ashkenazy"]),
    ("Mischa Maisky & Martha Argerich", ["maisky", "argerich"]),
    ("Emma Kirkby, The Academy of Ancient Music, Christopher Hogwood", ["kirkby", "aam", "hogwood"]),
    ("Kirill Petrenko, Berliner Philharmoniker", ["petrenko_k", "bpo"]),
    ("Beaux Arts Trio", ["beauxarts"]),
]
JUNK = ["Various Artists", "Anonymous", "Orchestra", "Soloists", "Chor", "Ensemble",
        "Unknown Artist", "[unknown]", "Traditional"]

# A textbook filter: performer occupations and ensemble classes, direct statements only.
OCC = ["Q158852", "Q486748", "Q1259917", "Q13219637", "Q177220", "Q2865819", "Q765778",
       "Q5371902", "Q639669"]
ENS = ["Q42998", "Q239582", "Q131186", "Q207338", "Q215380", "Q2088357"]
FILTER_CLASS = "haswbstatement:" + "|".join([f"P106={q}" for q in OCC] + [f"P31={q}" for q in ENS])
FILTER_MB = "haswbstatement:P434"  # item has a MusicBrainz artist ID

NAVIDROME_SPLIT = [" / ", " feat. ", " feat ", " ft. ", " ft ", "; "]
ENSEMBLE_WORDS = re.compile(r"orchest|philharm|choir|chor|quart|trio|ensemble|consort|academy|"
                            r"soloists|kapelle|scholars|sixteen|musicus|armonico|vocale|hesp", re.I)


def get(url, params=None):
    global requests
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    requests += 1
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                time.sleep(0.35)
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (429, 503) and attempt < 2:
                time.sleep(int(e.headers.get("Retry-After", 5)))
                continue
            raise


def wbsearch(name):
    d = get(WD, dict(action="wbsearchentities", search=name, language="en", type="item",
                     limit=5, format="json"))
    return [x["id"] for x in d["search"]]


def cirrus(name, flt=""):
    d = get(WD, dict(action="query", list="search", srsearch=f"{name} {flt}".strip(),
                     srlimit=5, srprop="", format="json"))
    return [x["title"] for x in d["query"]["search"]]


def fold(s):
    s = unicodedata.normalize("NFKD", s.lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    return set(re.findall(r"[a-z0-9]+", s)) - {"the", "sir", "dame"}


def names_of(qids):
    """Labels and aliases in all languages, for the token-set rule."""
    out = {}
    for i in range(0, len(qids), 50):
        d = get(WD, dict(action="wbgetentities", ids="|".join(qids[i:i + 50]),
                         props="labels|aliases", format="json"))
        for q, e in d["entities"].items():
            n = {v["value"] for v in e.get("labels", {}).values()}
            n |= {a["value"] for al in e.get("aliases", {}).values() for a in al}
            out[q] = n
    return out


def token_match(tag, names):
    t = fold(tag)
    return any(fold(n) == t for n in names)


def split_naive(s):
    return [p.strip() for p in re.split(r"\s*(?:;|/|,|&| and | feat\.? | ft\.? )\s*", s) if p.strip()]


def split_navidrome(s):
    parts = [s]
    for sep in NAVIDROME_SPLIT:
        parts = [x for p in parts for x in p.split(sep)]
    return [p.strip() for p in parts if p.strip()]


def split_smart(s):
    """Navidrome separators, then comma, '&' and ' and '. Rejoin 'Surname, Given names'."""
    out = []
    for p in split_navidrome(s):
        pieces = [x.strip() for x in re.split(r",|&| and ", p) if x.strip()]
        i = 0
        while i < len(pieces):
            a = pieces[i]
            b = pieces[i + 1] if i + 1 < len(pieces) else None
            if (b and len(a.split()) == 1 and len(b.split()) <= 3
                    and not ENSEMBLE_WORDS.search(a + " " + b)):
                out.append(f"{b} {a}")
                i += 2
            else:
                out.append(a)
                i += 1
    return out


def sparql(qids):
    q = ("SELECT ?p ?b ?d ?inc ?end ?img ?logo ?mb ?dc ?en ?de ?lang ?desc WHERE { VALUES ?p { "
         + " ".join("wd:" + x for x in qids) + " } "
         "OPTIONAL{?p wdt:P569 ?b} OPTIONAL{?p wdt:P570 ?d} OPTIONAL{?p wdt:P571 ?inc} "
         "OPTIONAL{?p wdt:P576 ?end} OPTIONAL{?p wdt:P18 ?img} OPTIONAL{?p wdt:P154 ?logo} "
         "OPTIONAL{?p wdt:P434 ?mb} OPTIONAL{?p wdt:P1953 ?dc} "
         "OPTIONAL{?en schema:about ?p; schema:isPartOf <https://en.wikipedia.org/>} "
         "OPTIONAL{?de schema:about ?p; schema:isPartOf <https://de.wikipedia.org/>} "
         "OPTIONAL{?p schema:description ?desc. BIND(LANG(?desc) AS ?lang) "
         'FILTER(?lang IN ("en","de","fr","it","es","nl"))} }')
    d = get("https://query.wikidata.org/sparql", {"query": q, "format": "json"})
    facts = {}
    for r in d["results"]["bindings"]:
        q_ = r["p"]["value"].rsplit("/", 1)[1]
        f = facts.setdefault(q_, {"desc": {}, "img": set()})
        for k in ("b", "d", "inc", "end", "logo", "mb", "dc", "en", "de"):
            if k in r:
                f[k] = r[k]["value"]
        if "img" in r:
            f["img"].add(urllib.parse.unquote(r["img"]["value"].rsplit("/", 1)[1]))
        if "desc" in r:
            f["desc"][r["lang"]["value"]] = r["desc"]["value"]
    return facts


def licences(files):
    out = {}
    for i in range(0, len(files), 50):
        d = get("https://commons.wikimedia.org/w/api.php",
                dict(action="query", titles="|".join("File:" + f for f in files[i:i + 50]),
                     prop="imageinfo", iiprop="extmetadata", format="json",
                     iiextmetadatafilter="LicenseShortName|AttributionRequired|Artist"))
        norm = {n["to"]: n["from"] for n in d["query"].get("normalized", [])}
        for p in d["query"]["pages"].values():
            m = {k: v["value"] for k, v in p.get("imageinfo", [{}])[0].get("extmetadata", {}).items()}
            out[norm.get(p["title"], p["title"])[5:]] = m
    return out


def main():
    strategies = {
        "A wbsearchentities": lambda n: wbsearch(n),
        "B search, no filter": lambda n: cirrus(n),
        "C search, class filter": lambda n: cirrus(n, FILTER_CLASS),
        "D search, has P434": lambda n: cirrus(n, FILTER_MB),
    }
    score = {s: Counter() for s in strategies}
    hits_d = {}
    print("== single names: variant | truth | first hit per strategy")
    for v, key in VARIANTS:
        kind = "ens" if key in ENSEMBLES else "per"
        row = []
        for s, f in strategies.items():
            h = f(v)
            if s.startswith("D"):
                hits_d[v] = h
            ok = "right" if h and h[0] == TRUTH[key] else ("none" if not h else "wrong")
            score[s][(kind, ok)] += 1
            row.append(f"{s[0]}={h[0] if h else '-'}{'' if ok == 'right' else '!' + ok}")
        print(f"{v!r} | {TRUTH[key]} | " + " ".join(row))
    print("== score: strategy | persons right/wrong/none | ensembles right/wrong/none")
    for s, c in score.items():
        print(s, "| per", c[("per", "right")], c[("per", "wrong")], c[("per", "none")],
              "| ens", c[("ens", "right")], c[("ens", "wrong")], c[("ens", "none")])

    print("== token-set rule on D first hits: accept when a label or alias has the same words")
    firsts = sorted({h[0] for h in hits_d.values() if h})
    nm = names_of(firsts)
    acc = Counter()
    for v, key in VARIANTS:
        h = hits_d[v]
        if not h:
            continue
        a = token_match(v, nm.get(h[0], ()))
        right = h[0] == TRUTH[key]
        acc[(a, right)] += 1
        if a and not right:
            print("  accepted but wrong:", v, h[0])
    print("  accepted+right", acc[(True, True)], "accepted+wrong", acc[(True, False)],
          "asked+right", acc[(False, True)], "asked+wrong", acc[(False, False)])

    print("== ambiguous surnames, D")
    for v, keys in AMBIGUOUS:
        h = cirrus(v, FILTER_MB)
        print(v, h[:3], "candidates", [TRUTH[k] for k in keys])
    for v, occ in [("Kleiber", "Q158852"), ("Petrenko", "Q158852"), ("Gould", "Q486748"),
                   ("Davis", "Q158852")]:
        print(v, "with role filter", occ, cirrus(v, f"{FILTER_MB} haswbstatement:P106={occ}")[:3])

    print("== junk tags, D and C first hits")
    for v in JUNK:
        print(v, "D", cirrus(v, FILTER_MB)[:2], "C", cirrus(v, FILTER_CLASS)[:2])

    print("== album-wide strings: split, then D on each part")
    whole = Counter()
    whole_hits = {}
    for s, keys in ALBUM_ARTISTS:
        want = {TRUTH[k] for k in keys}
        h = cirrus(s, FILTER_MB)
        whole["first hit in set" if h and h[0] in want else "no"] += 1
        if h:
            whole_hits[s] = h[0]
        print(f"{s!r} whole -> {h[:2]}")
    print("  whole string, first hit is one of the performers:", dict(whole))
    wn = names_of(sorted(set(whole_hits.values())))
    for s, q in whole_hits.items():
        print(f"  keep whole {s!r} ({q})? token rule says", token_match(s, wn[q]))
    for name, fn in [("naive", split_naive), ("navidrome", split_navidrome), ("smart", split_smart)]:
        exact = parts_ok = parts_all = 0
        for s, keys in ALBUM_ARTISTS:
            want = [TRUTH[k] for k in keys]
            parts = fn(s)
            got = []
            for p in parts:
                h = cirrus(p, FILTER_MB)
                got.append(h[0] if h else None)
            parts_all += len(want)
            parts_ok += len(set(got) & set(want))
            exact += set(got) == set(want) and len(got) == len(want)
            if set(got) != set(want):
                print(f"  {name}: {s!r} -> {parts} -> {got}")
        print(f"  split {name}: exact {exact}/{len(ALBUM_ARTISTS)}, performers found {parts_ok}/{parts_all}")

    print("== facts for the right items (one SPARQL request)")
    qids = sorted(set(TRUTH.values()))
    facts = sparql(qids)
    ens_q = {TRUTH[k] for k in ENSEMBLES}
    stats = Counter()
    files = {}
    for q in qids:
        f = facts.get(q, {"desc": {}, "img": set()})
        kind = "ens" if q in ens_q else "per"
        stats[(kind, "n")] += 1
        for k in ("b", "d", "inc", "end", "logo", "mb", "dc", "en", "de"):
            stats[(kind, k)] += k in f
        stats[(kind, "img")] += bool(f["img"])
        for lang in f["desc"]:
            stats[(kind, "desc_" + lang)] += 1
        en = f["desc"].get("en", "")
        stats[(kind, "en_years")] += bool(re.search(r"\d{4}", en))
        if f["img"]:
            files[q] = sorted(f["img"])[0]
        print(q, kind, f.get("b", "")[:4], f.get("d", "")[:4], f.get("inc", "")[:4],
              "| en:", en, "| de:", f["desc"].get("de", "-"), "| img:", sorted(f["img"])[:1])
    for kind in ("per", "ens"):
        print(kind, {k[1]: v for k, v in sorted(stats.items()) if k[0] == kind})

    print("== Commons licence of the P18 files")
    lic = licences(sorted(set(files.values())))
    by = {"per": Counter(), "ens": Counter()}
    for q, fname in files.items():
        m = lic.get(fname, {})
        kind = "ens" if q in ens_q else "per"
        by[kind][(m.get("LicenseShortName", "?"), m.get("AttributionRequired", "?"))] += 1
    for kind, c in by.items():
        print(kind, c.most_common())
    print("total requests", requests)


if __name__ == "__main__":
    main()
