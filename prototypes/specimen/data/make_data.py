"""Builds specimen.json: the data snapshot for the design specimen (map sz-rs30.1.83, ticket sz-rs30.1.83.2).

Usage: python3 make_data.py <library Classical folder> <work dir>
Needs ffmpeg, mutagen, curl and network access to GitHub, Wikidata and Commons.

The snapshot holds what Navidrome 0.64.2 serves through OpenSubsonic, so the specimen sees the
same fields as the app. Two sets:
- flo: Flo's own tags, for all of Chopin and about 30 works across the eras. Flo allows his tags in
  the public prototypes. The scan reads the library through symlinks; no audio leaves the disk.
- weak: three recordings in another tagging style, as silent MP3 files of the same length.
Embedded cover art never reaches the snapshot. Each album gets a public-domain painting from
Commons instead, chosen by the composition year of its works, and loaded at runtime. Two albums
get none.
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request

import mutagen
from mutagen.id3 import ID3, TALB, TCOM, TCON, TDRC, TIT2, TPE1, TPE2, TPOS, TRCK

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
AGENT = "KlassikSpecimen/1.0 (https://github.com/whnr/klassik)"
BASE = "http://127.0.0.1:4533/rest/"
AUTH = {"u": "fixture", "p": "fixture", "v": "1.16.1", "c": "specimen", "f": "json"}

# Work folders of the Classical layout (Composer/Work). Chopin is whole: his long list is a test.
FLO = ["Chopin"] + [
    "Gabrieli/Sanctus and Benedictus a 12, Ch. 47",
    "Praetorius/Es ist ein Ros entsprungen",
    "Schütz/Musikalische Exequien, Op. 7",
    "Hammerschmidt/Machet die Tore weit",
    "Bach/Goldberg-Variationen, BWV 988",
    "Bach/Brandenburgisches Konzert Nr. 5 D-Dur, BWV 1050",
    "Bach/Matthäus-Passion, BWV 244",
    "Vivaldi/Violin Concerto in E major, Op. 8 No. 1, RV 269 'Spring'",
    "Vivaldi/Violin Concerto in F minor, Op. 8 No. 4, RV 297 'Winter'",
    "Handel/Water Music Suite No. 1 in F major, HWV 348",
    "Haydn/Die Schöpfung, Hob. XXI_2",
    "Haydn/Symphony No. 94 in G major, Hob. I_94",
    "Mozart/Requiem in D minor, K. 626",
    "Mozart/Clarinet Concerto in A major, K. 622",
    "Beethoven/Symphony No. 5 in C minor, Op. 67",
    "Beethoven/Symphony No. 9 in D minor, Op. 125",
    "Beethoven/Piano Concerto No. 5 in E-flat major, Op. 73",
    "Schubert/Symphony No. 8 in B minor, D 759",
    "Mendelssohn/A Midsummer Night's Dream, Op. 61",
    "Brahms/Ein deutsches Requiem, Op. 45",
    "Brahms/Violin Concerto in D major, Op. 77",
    "Dvořák/Symphony No. 9 in E minor, Op. 95",
    "Dvořák/Cello Concerto in B minor, Op. 104",
    "Tchaikovsky/Symphony No. 6 in B minor, Op. 74",
    "Strauss/Don Juan, Op. 20",
    "Mahler/Symphony No. 2 in C minor",
    "Fauré/Masques et bergamasques, Op. 112",
    "Bonis/Cleopatra's Dream, Op. 180",
    "Boulanger/On a Spring Morning",
    "Sohy/Mystical Dance, Op. 19",
    "Ravel/Boléro, M. 81",
    "Stravinsky/The Rite of Spring",
    "Shostakovich/Symphony No. 5 in D minor, Op. 47",
    "Vaughan Williams/Fantasia on Greensleeves",
    "Zender/Schuberts Winterreise",
]

# Another library's style: no work, movement or role tags; all performers in one artist string;
# the work and movement only in the title. Each album is weak in its own way.
WEAK = [
    {   # Surname-only composer, "Work: I. Movement".
        "album": "Beethoven: Symphony No. 7", "composer": "Beethoven", "genre": "Classical", "sep": ": ",
        "sources": ["Beethoven/Symphony No. 7 in A major, Op. 92/Wiener Philharmoniker, Karl Böhm"],
    },
    {   # No composer tag; the work is a nickname.
        "album": "Vivaldi - The Four Seasons", "composer": None, "genre": "Classical", "sep": ": ",
        "works": {"RV 315": "Summer", "RV 293": "Autumn"},
        "sources": ["Vivaldi/Violin Concerto in G minor, Op. 8 No. 2, RV 315 'Summer'/Venice Baroque Orchestra, Andrea Marcon",
                    "Vivaldi/Violin Concerto in F major, Op. 8 No. 3, RV 293 'Autumn'/Venice Baroque Orchestra, Andrea Marcon"],
    },
    {   # No genre, "Work - I. Movement".
        "album": "Schubert: The Great C Major", "composer": "Franz Schubert", "genre": None, "sep": " - ",
        "sources": ["Schubert/Symphony No. 9 in C major, D 944/Gewandhausorchester Leipzig, Herbert Blomstedt"],
    },
]

# Albums without a cover, one in each set: the specimen must show that state too.
NO_COVER = {"Weihnachtshistorie", "Schubert: The Great C Major"}

ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
AUDIO = (".mp3", ".flac", ".m4a")
# Fields that describe the file or the server, not the music, or that would leak the real covers.
DROP = {"path", "coverArt", "size", "bitRate", "contentType", "suffix", "created", "isDir", "isVideo", "type",
        "mediaType", "parent", "albumId", "artistId", "bpm", "samplingRate", "channelCount", "bitDepth",
        "replayGain", "artistImageUrl", "played", "playCount", "starred", "userRating", "explicitStatus",
        "transcodedContentType", "transcodedSuffix"}


def raw(path, name):
    """One tag value as text, by its ID3, Vorbis or MP4 name."""
    f = mutagen.File(path)
    t = (f and f.tags) or {}
    for key in (f"TXXX:{name}", name, name.lower(), f"----:com.apple.iTunes:{name}"):
        if key in t:
            v = t[key]
            v = v.text[0] if hasattr(v, "text") else v[0]
            return v.decode() if isinstance(v, bytes) else str(v)
    return ""


def year(path):
    match = re.search(r"\d{4}", raw(path, "COMPOSITIONDATE"))
    return int(match.group()) if match else None


def audio(folder):
    return [p for p in sorted(folder.rglob("*", recurse_symlinks=True)) if p.suffix in AUDIO]


def build_library(lib, music):
    """Returns the composition year of each weak album; the scan of the flo set reads its own."""
    if music.exists():
        shutil.rmtree(music)
    for rel in FLO:
        link = music / "flo" / rel
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(lib / rel, target_is_directory=True)
    return {a["album"]: build_weak(lib, music / "weak" / a["album"].replace(":", ""), a) for a in WEAK}


def build_weak(lib, folder, album):
    folder.mkdir(parents=True)
    files = [p for src in album["sources"] for p in audio(lib / src)]
    for n, src in enumerate(files, 1):
        work, movement = raw(src, "WORK") or raw(src, "TIT1"), raw(src, "MVNM") or raw(src, "MOVEMENTNAME")
        for key, nick in album.get("works", {}).items():
            work = nick if key in work else work
        number = int(raw(src, "MOVEMENT") or 0)
        title = f"{work}{album['sep']}{ROMAN[number - 1]}. {movement}" if number else raw(src, "TIT2")
        performers = src.parent.name
        out = folder / f"{n:02d}.mp3"
        seconds = mutagen.File(src).info.length  # pyright: ignore[reportOptionalMemberAccess]
        subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "anullsrc=r=8000:cl=mono",
                        "-t", f"{seconds:.2f}", "-b:a", "8k", str(out)], check=True)
        id3 = ID3()
        id3.add(TIT2(encoding=3, text=title))
        id3.add(TALB(encoding=3, text=album["album"]))
        id3.add(TPE1(encoding=3, text=performers))
        id3.add(TPE2(encoding=3, text=performers))
        id3.add(TRCK(encoding=3, text=str(n)))
        id3.add(TPOS(encoding=3, text="1"))
        id3.add(TDRC(encoding=3, text=raw(src, "TDRC")[:4]))
        if album["composer"]:
            id3.add(TCOM(encoding=3, text=album["composer"]))
        if album["genre"]:
            id3.add(TCON(encoding=3, text=album["genre"]))
        id3.save(out)
    return year(files[0])


def composition_years(music):
    """Median COMPOSITIONDATE year per album name. The server drops this tag; the covers need it."""
    years = {}
    for path in audio(music / "flo"):
        y = year(path)
        album = raw(path, "TALB") or raw(path, "ALBUM") or raw(path, "©alb")
        if y and album:
            years.setdefault(album, []).append(y)
    return {name: sorted(ys)[len(ys) // 2] for name, ys in years.items()}


def api(method, **params):
    url = BASE + method + "?" + urllib.parse.urlencode({**AUTH, **params})
    with urllib.request.urlopen(url) as r:
        body = json.load(r)["subsonic-response"]
    if body["status"] != "ok":
        raise RuntimeError(f"{method}: {body}")
    return body


def clean(item):
    if isinstance(item, dict):
        return {k: clean(v) for k, v in item.items() if k not in DROP and v not in ("", [], None)}
    if isinstance(item, list):
        return [clean(v) for v in item]
    return item


def fetch(url, data=None, accept="application/json"):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": AGENT, "Accept": accept})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def paintings():
    """Famous paintings in seven large collections, with a Commons file and a year."""
    query = (HERE / "paintings.rq").read_text()
    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": query})
    rows = fetch(url, accept="application/sparql-results+json")["results"]["bindings"]
    seen, out = set(), []
    for b in sorted(rows, key=lambda b: (-int(b["links"]["value"]), b["p"]["value"])):
        if b["p"]["value"] in seen:
            continue
        seen.add(b["p"]["value"])
        out.append({"file": urllib.parse.unquote(b["img"]["value"].rsplit("/", 1)[1]),
                    "title": b["pLabel"]["value"], "painter": b["cLabel"]["value"],
                    "year": int(b["year"]["value"]), "wikidata": b["p"]["value"]})
    return out


def commons(files):
    """Thumbnail URL, page and licence for each Commons file; public domain only."""
    info = {}
    for i in range(0, len(files), 40):
        params = {"action": "query", "format": "json", "prop": "imageinfo", "iiprop": "url|extmetadata",
                  "iiurlwidth": "1200", "iiextmetadatafilter": "LicenseShortName",
                  "titles": "|".join("File:" + f for f in files[i:i + 40])}
        pages = fetch("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params))
        names = {n["to"]: n["from"] for n in pages["query"].get("normalized", [])}
        for page in pages["query"]["pages"].values():
            if "imageinfo" not in page:
                continue
            ii = page["imageinfo"][0]
            licence = ii["extmetadata"].get("LicenseShortName", {}).get("value", "")
            if licence.lower().startswith("public domain"):
                info[names.get(page["title"], page["title"])[5:]] = {
                    "url": ii["thumburl"], "page": ii["descriptionurl"], "licence": licence}
    return info


def covers(albums, years):
    """Each album gets the unused painting nearest the composition year of its works, or None."""
    pool = paintings()
    info = commons([p["file"] for p in pool])
    pool = [p | info[p["file"]] for p in pool if p["file"] in info]
    out = {}
    for album in sorted(albums, key=lambda a: (years.get(a["name"], 1800), a["name"])):
        if album["name"] in NO_COVER:
            out[album["id"]] = None
            continue
        year = years.get(album["name"], 1800)
        best = min(pool, key=lambda p: abs(p["year"] - year))
        pool.remove(best)
        out[album["id"]] = {k: best[k] for k in ("title", "painter", "year", "url", "page", "licence", "wikidata")}
    return out


def main():
    lib, work = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve()
    music = work / "music"
    years = build_library(lib, music) | composition_years(music)
    shutil.rmtree(work / "data", ignore_errors=True)
    subprocess.run([str(REPO / "scripts" / "fixture-server.sh"), str(work)], check=True)
    try:
        listed = api("getAlbumList2", type="alphabeticalByName", size=500)["albumList2"]["album"]
        albums = [api("getAlbum", id=a["id"])["album"] for a in listed]
        artists = [a for i in api("getArtists")["artists"].get("index", []) for a in i["artist"]]
    finally:
        pid = (work / "navidrome.pid").read_text().strip()
        subprocess.run(["kill", pid], check=False)
    weak_names = {a["album"] for a in WEAK}
    snapshot = {
        "about": "Specimen data for the Klassik design map. OpenSubsonic responses of Navidrome 0.64.2. "
                 "Set 'flo': Flo's tags. Set 'weak': another tagging style. Covers: public-domain paintings "
                 "from Wikimedia Commons, credit with each. Regenerate with make_data.py.",
        "server": "Navidrome 0.64.2",
        "albums": [dict(clean(a), set="weak" if a["name"] in weak_names else "flo") for a in albums],
        "artists": [clean(a) for a in artists],
        "covers": covers(albums, years),
    }
    out = HERE / "specimen.json"
    out.write_text(json.dumps(snapshot, ensure_ascii=False, indent=1) + "\n")
    songs = sum(len(a.get("song", [])) for a in snapshot["albums"])
    print(f"{out}: {len(albums)} albums, {songs} songs, {len(artists)} artists, {len(snapshot['covers'])} covers")


if __name__ == "__main__":
    main()
