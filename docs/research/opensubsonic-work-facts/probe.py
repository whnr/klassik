"""Writes probe files with sz-rs30.2 style tags and weak tags, for a throwaway Navidrome.

Usage: python3 probe.py <music-dir>
Audio is a generated sine tone. Every date has a distinct value, so the answer shows which tag reached which field.
"""
import pathlib
import subprocess
import sys

from mutagen.flac import FLAC
from mutagen.id3 import (COMM, GRP1, ID3, MVNM, TALB, TCOM, TCON, TDOR, TDRC, TDRL, TIPL, TIT1, TIT2, TIT3, TMCL, TPE1,
                         TPE2, TPE3, TRCK, TSOC, TXXX, TSOP, TSOA, TSOT)

WORK = "Symphony No. 4 in E minor, Op. 98"
MBID = "11111111-2222-4333-8444-555555555555"  # not a real work ID


def tone(path, flac=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    codec = ["-codec:a", "flac"] if flac else ["-codec:a", "libmp3lame", "-b:a", "64k"]
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=330:duration=1", "-ac", "1",
                    *codec, str(path)], check=True)


def contract(root):
    for n, name in enumerate(["Allegro non troppo", "Andante moderato"], 1):
        p = root / "Contract" / f"{n:02d}.mp3"
        tone(p)
        t = ID3()
        t.add(TIT2(encoding=3, text=f"{WORK}: {n}. {name}"))
        t.add(TALB(encoding=3, text="Contract Album"))
        t.add(TPE2(encoding=3, text=["Probe Orchestra", "Probe Conductor"]))
        t.add(TPE1(encoding=3, text=["Probe Soloist", "Probe Orchestra", "Probe Conductor"]))
        t.add(TPE3(encoding=3, text="Probe Conductor"))
        t.add(TMCL(encoding=3, people=[["orchestra", "Probe Orchestra"], ["violin", "Probe Soloist"]]))
        t.add(TIPL(encoding=3, people=[["arranger", "Probe Arranger"]]))
        t.add(TCOM(encoding=3, text="Johannes Brahms"))
        t.add(TSOC(encoding=3, text="Brahms, Johannes"))
        t.add(TIT1(encoding=3, text=WORK))
        t.add(TXXX(encoding=3, desc="WORK", text=WORK))
        t.add(MVNM(encoding=3, text=name))
        t.add(TXXX(encoding=3, desc="MOVEMENT", text=str(n)))
        t.add(TXXX(encoding=3, desc="MOVEMENTTOTAL", text="2"))
        t.add(TXXX(encoding=3, desc="MusicBrainz Work Id", text=MBID))
        t.add(GRP1(encoding=3, text="Probe Grouping"))
        t.add(TCON(encoding=3, text=["Classical", "Orchestral", "Romantic"]))
        t.add(TRCK(encoding=3, text=f"{n}/2"))
        t.add(TSOT(encoding=3, text=f"sorttitle {n}"))
        t.add(TSOA(encoding=3, text="sortalbum"))
        # Dates: each candidate tag gets its own value.
        t.add(TDRC(encoding=3, text="1999-11"))  # recording
        t.add(TDRL(encoding=3, text="2000-05-06"))  # edition release
        t.add(TDOR(encoding=3, text="1885-10-25"))  # original release
        t.add(TXXX(encoding=3, desc="COMPOSITIONDATE", text="1884-1885"))
        t.add(TXXX(encoding=3, desc="COMPOSED", text="1884"))
        t.add(TXXX(encoding=3, desc="WORKDATE", text="1883"))
        t.add(TXXX(encoding=3, desc="ORIGINALYEAR", text="1882"))
        t.add(COMM(encoding=3, lang="eng", desc="", text="composed 1884-1885, premiere 1885"))
        t.add(TIT3(encoding=3, text="subtitle 1881"))
        t.save(p, v2_version=4)


def weak(root):
    # Weak 1: title, artist, album only.
    p = root / "Weak" / "01.mp3"
    tone(p)
    t = ID3()
    t.add(TIT2(encoding=3, text=f"{WORK}: 1. Allegro non troppo"))
    t.add(TPE1(encoding=3, text="Probe Orchestra"))
    t.add(TALB(encoding=3, text="Weak Album"))
    t.save(p, v2_version=4)
    # Weak 2: composer, genre and year, no work tags (a typical Picard-less library).
    p = root / "Weak" / "02.mp3"
    tone(p)
    t = ID3()
    t.add(TIT2(encoding=3, text="Nocturne in E-flat major, Op. 9 No. 2"))
    t.add(TPE1(encoding=3, text="Probe Pianist"))
    t.add(TALB(encoding=3, text="Weak Album 2"))
    t.add(TCOM(encoding=3, text="Frederic Chopin"))
    t.add(TCON(encoding=3, text="Classical"))
    t.add(TDRC(encoding=3, text="2011"))
    t.save(p, v2_version=4)
    # Weak 3: only MusicBrainz Work Id on top of weak 2.
    p = root / "Weak" / "03.mp3"
    tone(p)
    t = ID3()
    t.add(TIT2(encoding=3, text="Etude Op. 10 No. 3"))
    t.add(TPE1(encoding=3, text="Probe Pianist"))
    t.add(TALB(encoding=3, text="Weak Album 3"))
    t.add(TCOM(encoding=3, text="Frederic Chopin"))
    t.add(TXXX(encoding=3, desc="MusicBrainz Work Id", text="66666666-2222-4333-8444-555555555555"))
    t.save(p, v2_version=4)


def flac(root):
    p = root / "Flac" / "01.flac"
    tone(p, flac=True)
    f = FLAC(p)
    f.update(title="Piece", album="Flac Album", artist="Probe Pianist", composer="Frederic Chopin",
             composersort="Chopin, Frederic", work="Etude Op. 10 No. 3", musicbrainz_workid="77777777-2222-4333-8444-555555555555",
             movementname="Lento", movement="1", movementtotal="1", date="2012", originaldate="1832",
             compositiondate="1832-1833", composed="1832", comment="composed 1832", genre=["Classical", "Piano", "Romantic"])
    f.save()


if __name__ == "__main__":
    root = pathlib.Path(sys.argv[1])
    contract(root)
    weak(root)
    flac(root)
