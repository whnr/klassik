# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Writes the short gapless fixtures of KlassikTests/Fixtures/Formats, one pair of tracks per audio format.

  uv run --script scripts/format_fixtures.py KlassikTests/Fixtures/Formats

Both tracks of a pair cut one continuous glide, 0.5 sin(2π(300 t + 25 t²)) at 44.1 kHz mono, so a join that
loses or repeats a sample shows. The sample counts must match `FormatFixtures.lengths` in the tests.
Needs ffmpeg on PATH. The audio is generated, so the repository carries no copyrighted material.
"""

import pathlib
import subprocess
import sys

RATE = 44100
LENGTHS = (22051, 18017)

# The ffmpeg output arguments of each format, and the file extension.
FORMATS = {
    "aac": ("m4a", ["-c:a", "aac", "-b:a", "128k"]),
    "alac": ("m4a", ["-c:a", "alac", "-sample_fmt", "s16p"]),
    # The moov box first, as a server that optimizes M4A files for streaming sends it.
    "aac-fast": ("m4a", ["-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]),
    "alac-fast": ("m4a", ["-c:a", "alac", "-sample_fmt", "s16p", "-movflags", "+faststart"]),
    "wav": ("wav", ["-c:a", "pcm_s16le"]),
    "aiff": ("aiff", ["-c:a", "pcm_s16be"]),
    "flac": ("flac", ["-c:a", "flac", "-sample_fmt", "s16"]),
    "mp3": ("mp3", ["-c:a", "libmp3lame", "-b:a", "128k", "-write_xing", "1"]),
    "mp3-bare": ("mp3", ["-c:a", "libmp3lame", "-b:a", "128k", "-write_xing", "0", "-write_id3v2", "0"]),
}


def glide(movement: int) -> str:
    """The lavfi source for one track: the glide, counted from the work's start."""
    start = sum(LENGTHS[: movement - 1])
    t = f"(t+{start}/{RATE})"
    return (
        f"aevalsrc=0.5*sin(2*PI*(300*{t}+25*{t}*{t})):s={RATE}:d={LENGTHS[movement - 1] / RATE + 1},"
        f"atrim=end_sample={LENGTHS[movement - 1]}"
    )


# Long fast-start tracks, so that a prefix of the file holds more than the 8 KB the system M4A reader reads first.
LONG_SECONDS = 8
LONG = {
    "aac-long": ["-c:a", "aac", "-b:a", "48k", "-movflags", "+faststart"],
    "alac-long": ["-c:a", "alac", "-sample_fmt", "s16p", "-movflags", "+faststart"],
}


def main(out: pathlib.Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for name, (ext, args) in FORMATS.items():
        for movement in (1, 2):
            target = out / f"{name}-{movement}.{ext}"
            subprocess.run(
                ["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", glide(movement), "-map_metadata", "-1"]
                + args
                + [str(target)],
                check=True,
            )
            print(target)
    source = f"aevalsrc=0.5*sin(2*PI*(300*t+25*t*t)):s={RATE}:d={LONG_SECONDS}"
    for name, args in LONG.items():
        target = out / f"{name}-1.m4a"
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", source, "-map_metadata", "-1"]
            + args
            + [str(target)],
            check=True,
        )
        print(target)


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]))
