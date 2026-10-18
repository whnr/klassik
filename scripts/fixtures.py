"""Generates a small classical fixture library: sine-tone MP3s with classical tags.

Usage: python3 scripts/fixtures.py <output-dir>
Needs ffmpeg on PATH and mutagen. The audio is generated, so the repo carries no copyrighted
material. Tags follow the convention in the library epic: Navidrome 0.64 drops the ID3 MVIN
frame, so movement number and total go into TXXX:MOVEMENT and TXXX:MOVEMENTTOTAL.
"""
import pathlib
import subprocess
import sys

from mutagen.flac import FLAC
from mutagen.id3 import GRP1, ID3, TALB, TCOM, TCON, TDRC, TDRL, TIT2, TMCL, TPE1, TPE2, TPE3, TPOS, TRCK, TXXX, MVNM

# (album, album artist, genre, recording date, release date, tracks)
# track: (composer, work, movement name, movement number, movement total, performers, conductor, seconds or None for the glide,
#         optional GROUPING)
BEETHOVEN = "Ludwig van Beethoven"
BACH = "Johann Sebastian Bach"
MOZART = "Wolfgang Amadeus Mozart"
CHOPIN = "Frédéric Chopin"
BRAHMS = "Johannes Brahms"

ORCH_A = [("orchestra", "Testing Philharmonic")]
ORCH_B = [("orchestra", "Sine Wave Chamber Orchestra")]

B5 = "Symphony No. 5 in C minor, Op. 67"
B5_MOVEMENTS = ["Allegro con brio", "Andante con moto", "Scherzo. Allegro", "Allegro"]
SUITE = "Cello Suite No. 1 in G major, BWV 1007"
SUITE_MOVEMENTS = ["Prélude", "Allemande", "Courante", "Sarabande", "Menuets I & II", "Gigue"]
K467 = "Piano Concerto No. 21 in C major, K. 467"
K467_MOVEMENTS = ["Allegro maestoso", "Andante", "Allegro vivace assai"]
B4 = "Symphony No. 4 in E minor, Op. 98"
B4_MOVEMENTS = ["Allegro non troppo", "Andante moderato", "Allegro giocoso", "Allegro energico e passionato"]
MENDELSSOHN = "Felix Mendelssohn"
OP64 = "Violin Concerto in E minor, Op. 64"
OP64_MOVEMENTS = ["Allegro molto appassionato", "Andante", "Allegretto non troppo – Allegro molto vivace"]

# The movements of Op. 64 run into each other. Their audio is one continuous glide, cut at sample
# positions that are not MP3 frame boundaries, so a gap or an overlap in playback is audible and
# measurable. KlassikTests/GaplessTests.swift holds the same formula and lengths. ffmpeg writes too
# small a padding value for some lengths (up to 35 samples); these lengths get the exact value.
GLIDE_RATE = 44100
GLIDE_SAMPLES = [132301, 110017, 154441]

# ReplayGain tags of the 1990 recording of the Fifth. The peak allows less boost than the gain asks for.
REPLAYGAIN = {"Beethoven: Symphony No. 5": {"album_gain": "+6.00 dB", "album_peak": "0.800000",
                                            "track_gain": "+5.00 dB", "track_peak": "0.700000"}}


def piece(title, grouping, performer):
    """A work of one piece with no movements, as in a Chopin edition. The GROUPING tag names its set."""
    return (CHOPIN, title, "", 0, 0, [("piano", performer)], None, 2, grouping)


def work(composer, title, movements, performers, conductor, seconds=4, only=None):
    picked = only or range(1, len(movements) + 1)
    return [(composer, title, movements[n - 1], n, len(movements), performers, conductor, seconds) for n in picked]


ALBUMS = [
    ("Beethoven: Symphony No. 5", "Testing Philharmonic; Anna Probe", "Classical > Orchestral", "1990", "1991-03-01",
     work(BEETHOVEN, B5, B5_MOVEMENTS, ORCH_A, "Anna Probe")),
    ("Beethoven: Symphonies 4 & 5", "Sine Wave Chamber Orchestra; Carl Fixture", "Classical", "2015", "2016-05-20",
     work(BEETHOVEN, B5, B5_MOVEMENTS, ORCH_B, "Carl Fixture")),
    ("Bach: Cello Suites", "Clara Cellotest", "Classical > Chamber", "2004", "2005-01-10",
     work(BACH, SUITE, SUITE_MOVEMENTS, [("cello", "Clara Cellotest")], None, seconds=3)),
    ("Mozart: Piano Concertos 21 & 23", "Daniel Keys; Testing Philharmonic; Anna Probe", "Classical > Concerto", "1999", "2000-09-15",
     work(MOZART, K467, K467_MOVEMENTS, [("piano", "Daniel Keys")] + ORCH_A, "Anna Probe")),
    # A recital disc with only part of a work, for the completeness badge.
    ("Romantic Encores", "Sine Wave Chamber Orchestra; Carl Fixture", "Classical", "2021", "2022-02-02",
     work(BRAHMS, B4, B4_MOVEMENTS, ORCH_B, "Carl Fixture", only=[3])
     + work(MOZART, K467, K467_MOVEMENTS, [("piano", "Daniel Keys")] + ORCH_B, "Carl Fixture", only=[2])),
    ("Mendelssohn: Violin Concerto", "Eva Bogen; Testing Philharmonic; Anna Probe", "Classical > Concerto", "2008", "2009-04-01",
     work(MENDELSSOHN, OP64, OP64_MOVEMENTS, [("violin", "Eva Bogen")] + ORCH_A, "Anna Probe", seconds=None)),
    # Every piece is its own work. The set is only the GROUPING tag; the ninth and tenth nocturne have none.
    ("Chopin: Nocturnes", "Pia Nissimo", "Classical > Piano", "2012", "2013-01-01",
     [piece("Nocturne No. 1 in B-flat minor, Op. 9 No. 1", "Nocturnes, Op. 9", "Pia Nissimo"),
      piece("Nocturne No. 2 in E-flat major, Op. 9 No. 2", "Nocturnes, Op. 9", "Pia Nissimo"),
      piece("Nocturne No. 4 in F major, Op. 15 No. 1", "Nocturnes, Op. 15", "Pia Nissimo"),
      piece("Nocturne No. 20 in C-sharp minor, Op. posth.", None, "Pia Nissimo")]),
]

# Not classical: the default filter must leave this out.
JAZZ = ("Sine Standards", "Fixture Jazz Trio", "Jazz", "2010", "2010-06-01",
        [("Fixture Jazz Trio", None, "Blue Sine", 1, 0, [], None, 3), ("Fixture Jazz Trio", None, "Square Dance", 2, 0, [], None, 3)])


# Not classical: the glide again, lossless. FLAC has no encoder delay, so its movements must join without a trim.
FLAC_ALBUM = ("Glide in FLAC", "Fixture Lossless Trio", "Electronic", "2020", "2020-02-02", ["Rise", "Climb", "Peak"])


def encode(path, source):
    codec = ["-codec:a", "flac"] if str(path).endswith(".flac") else ["-codec:a", "libmp3lame", "-b:a", "64k"]
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", source, "-ac", "1", "-ar", "44100", *codec,
         str(path)],
        check=True)


def glide(movement):
    """Samples of the glide for one movement: 0.5 sin(2π(300 t + 25 t²)), t counted from the work's start."""
    start = sum(GLIDE_SAMPLES[:movement - 1])
    count = GLIDE_SAMPLES[movement - 1]
    t = f"(t+{start}/{GLIDE_RATE})"
    return (f"aevalsrc=0.5*sin(2*PI*(300*{t}+25*{t}*{t})):s={GLIDE_RATE}:d={count / GLIDE_RATE + 1},"
            f"atrim=end_sample={count}")


def tag(path, album, album_artist, genre, recorded, released, number, total, track):
    composer, work_title, movement, movement_no, movement_total, performers, conductor, _, *rest = track
    tags = ID3()
    tags.add(TALB(encoding=3, text=album))
    tags.add(TPE2(encoding=3, text=album_artist.split("; ")))
    tags.add(TCON(encoding=3, text=genre))
    tags.add(TDRC(encoding=3, text=recorded))
    tags.add(TDRL(encoding=3, text=released))
    tags.add(TRCK(encoding=3, text=f"{number}/{total}"))
    tags.add(TPOS(encoding=3, text="1/1"))
    if work_title:
        tags.add(TIT2(encoding=3, text=f"{work_title}: {roman(movement_no)}. {movement}" if movement_total > 1 else work_title))
        tags.add(TCOM(encoding=3, text=composer))
        tags.add(TXXX(encoding=3, desc="WORK", text=work_title))
        if movement_total:
            tags.add(MVNM(encoding=3, text=movement))
            tags.add(TXXX(encoding=3, desc="MOVEMENT", text=str(movement_no)))
            tags.add(TXXX(encoding=3, desc="MOVEMENTTOTAL", text=str(movement_total)))
        if rest and rest[0]:
            tags.add(GRP1(encoding=3, text=rest[0]))
        artists = [name for _, name in performers] + ([conductor] if conductor else [])
        tags.add(TPE1(encoding=3, text=artists))
    else:
        tags.add(TIT2(encoding=3, text=movement))
        tags.add(TPE1(encoding=3, text=composer))
    if conductor:
        tags.add(TPE3(encoding=3, text=conductor))
    if performers:
        tags.add(TMCL(encoding=3, people=[list(p) for p in performers]))
    for name, value in REPLAYGAIN.get(album, {}).items():
        tags.add(TXXX(encoding=3, desc=f"REPLAYGAIN_{name.upper()}", text=value))
    tags.save(path, v2_version=4)


def tag_flac(path, number, total, title):
    album, artist, genre, recorded, released, _ = FLAC_ALBUM
    tags = FLAC(path)
    tags.update(title=title, album=album, artist=artist, albumartist=artist, genre=genre, date=recorded,
                tracknumber=f"{number}/{total}", discnumber="1/1")
    tags.save()


def roman(n):
    return ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][n - 1]


def main(out):
    out = pathlib.Path(out)
    frequency = 220
    for album, album_artist, genre, recorded, released, tracks in ALBUMS + [JAZZ]:
        folder = out / album_artist.split("; ")[0] / album
        folder.mkdir(parents=True, exist_ok=True)
        for number, track in enumerate(tracks, 1):
            path = folder / f"{number:02d} {track[2] or track[1]}.mp3".replace("/", "-")
            seconds = track[7]
            encode(path, f"sine=frequency={frequency}:duration={seconds}" if seconds else glide(track[3]))
            tag(path, album, album_artist, genre, recorded, released, number, len(tracks), track)
            frequency += 20
    folder = out / FLAC_ALBUM[1] / FLAC_ALBUM[0]
    folder.mkdir(parents=True, exist_ok=True)
    for number, title in enumerate(FLAC_ALBUM[5], 1):
        path = folder / f"{number:02d} {title}.flac"
        encode(path, glide(number))
        tag_flac(path, number, len(FLAC_ALBUM[5]), title)
    print(f"wrote {sum(len(a[5]) for a in ALBUMS) + len(JAZZ[5]) + len(FLAC_ALBUM[5])} tracks to {out}")


if __name__ == "__main__":
    main(sys.argv[1])
