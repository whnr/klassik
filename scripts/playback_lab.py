# /// script
# requires-python = ">=3.12"
# dependencies = ["mutagen>=1.47"]
# ///
"""Builds the Klassik Playback Lab library and serves it with Navidrome.

  uv run --script scripts/playback_lab.py build --movement1 a.flac --movement2 b.flac --out lab-library
  uv run --script scripts/playback_lab.py serve --music lab-library

`build` encodes the two source files (FLAC 24/96) into one album. Each test case is one work with
movement 1 and movement 2, so Navidrome groups the two files as a continuous join. `serve` downloads
Navidrome once and runs it in the foreground on that folder. Needs ffmpeg on PATH; runs on Linux and
macOS. The source files stay outside the repository: it holds no copyrighted audio.
"""

import argparse
import dataclasses
import hashlib
import ipaddress
import json
import os
import pathlib
import platform
import secrets
import shutil
import socket
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request

from mutagen.id3 import TALB, TCOM, TCON, TDRC, TIT2, TPE1, TPE2, TPOS, TRCK, TXXX
from mutagen.mp4 import MP4
from mutagen.wave import WAVE

NAVIDROME_VERSION = "0.64.2"
PORT = 4533
USER = "lab"

ALBUM = "Playback Lab"
ARTIST = "Lab Ensemble"
COMPOSER = "Lab Composer"
MOVEMENTS = ("First movement", "Second movement")

# Fixed values: the lab tests that the tags are read, not that they are right.
REPLAYGAIN = {"replaygain_track_gain": "-6.50 dB", "replaygain_track_peak": "0.891251"}


@dataclasses.dataclass(frozen=True)
class Case:
    """One test case: the folder name, the file extension and the ffmpeg output arguments.

    `rates` gives the sample rate of movement 1 and movement 2 when it differs from the arguments'.
    `tags` are extra tags (ReplayGain) written to both movements."""

    slug: str
    title: str
    ext: str
    args: tuple[str, ...]
    rates: tuple[int, int] | None = None
    tags: tuple[tuple[str, str], ...] = ()


FLAC24 = ("-c:a", "flac", "-sample_fmt", "s32", "-bits_per_raw_sample", "24")
FLAC16 = ("-c:a", "flac", "-sample_fmt", "s16")

CASES = (
    Case("flac-24-96", "FLAC 24/96", "flac", (*FLAC24, "-ar", "96000"), tags=tuple(REPLAYGAIN.items())),
    Case("flac-16-44", "FLAC 16/44.1", "flac", (*FLAC16, "-ar", "44100")),
    Case("flac-24-192", "FLAC 24/192", "flac", (*FLAC24, "-ar", "192000")),
    Case(
        "alac-24-96",
        "ALAC 24/96",
        "m4a",
        ("-c:a", "alac", "-sample_fmt", "s32p", "-bits_per_raw_sample", "24", "-ar", "96000"),
    ),
    Case("alac-16-44", "ALAC 16/44.1", "m4a", ("-c:a", "alac", "-sample_fmt", "s16p", "-ar", "44100")),
    # ffmpeg's mp4 muxer writes the encoder delay as an edit list; the app must honor it for gapless.
    Case("aac-256", "AAC 256 with encoder delay", "m4a", ("-c:a", "aac", "-b:a", "256k", "-ar", "44100")),
    Case(
        "mp3-lame-header",
        "MP3 with LAME header",
        "mp3",
        ("-c:a", "libmp3lame", "-b:a", "320k", "-ar", "44100", "-write_xing", "1"),
        tags=tuple(REPLAYGAIN.items()),
    ),
    Case(
        "mp3-no-header",
        "MP3 without header",
        "mp3",
        ("-c:a", "libmp3lame", "-b:a", "320k", "-ar", "44100", "-write_xing", "0"),
    ),
    Case("wav", "WAV", "wav", ("-c:a", "pcm_s24le", "-ar", "96000", "-write_id3v2", "1")),
    Case("aiff", "AIFF", "aiff", ("-c:a", "pcm_s24be", "-ar", "96000", "-write_id3v2", "1")),
    Case("opus", "Opus", "opus", ("-c:a", "libopus", "-b:a", "160k", "-ar", "48000")),
    Case("rate-change", "Rate change 96 kHz then 44.1 kHz", "flac", FLAC24, rates=(96000, 44100)),
)


@dataclasses.dataclass(frozen=True)
class Job:
    """One file to encode, and the tags it must carry."""

    source: pathlib.Path
    target: pathlib.Path
    args: tuple[str, ...]
    tags: dict[str, str]


# The ID3 frames ffmpeg writes for the other formats. Tags without a frame go in a TXXX frame, as ffmpeg does.
ID3_FRAMES = {
    "title": TIT2,
    "album": TALB,
    "album_artist": TPE2,
    "artist": TPE1,
    "composer": TCOM,
    "genre": TCON,
    "date": TDRC,
    "disc": TPOS,
    "track": TRCK,
}


def metadata(case: Case, number: int, movement: int) -> dict[str, str]:
    """Tags of one file. Every case is its own disc, so track numbers never collide."""
    tags = {
        "title": MOVEMENTS[movement - 1],
        "album": ALBUM,
        "album_artist": ARTIST,
        "artist": ARTIST,
        "composer": COMPOSER,
        "genre": "Classical",
        "date": "2026",
        "disc": str(number),
        "track": str(movement),
        "work": case.title,
        "movementname": MOVEMENTS[movement - 1],
        "movement": str(movement),
        "movementtotal": str(len(MOVEMENTS)),
    }
    tags.update(case.tags)
    return tags


def ffmpeg_args(case: Case, number: int, movement: int, source: pathlib.Path, target: pathlib.Path) -> list[str]:
    """The complete ffmpeg argv for one file: audio only, source tags dropped, lab tags written."""
    args = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-nostdin",
        "-y",
        "-i",
        str(source),
        "-vn",
        "-map_metadata",
        "-1",
    ]
    codec = list(case.args)
    if case.rates:
        rate = str(case.rates[movement - 1])
        if "-ar" in codec:
            codec[codec.index("-ar") + 1] = rate
        else:
            codec += ["-ar", rate]
    args += codec
    for key, value in metadata(case, number, movement).items():
        # The mp4 muxer drops tags without an atom. write_m4a_tags adds them after the encode.
        if case.ext != "m4a" or key in M4A_ATOMS:
            args += ["-metadata", f"{key}={value}"]
    args.append(str(target))
    return args


def plan(movements: tuple[pathlib.Path, pathlib.Path], out: pathlib.Path) -> list[Job]:
    """The folder plan: <out>/<album>/<NN case>/<N movement>.<ext>, one folder per test case."""
    jobs = []
    for number, case in enumerate(CASES, start=1):
        folder = out / ALBUM / f"{number:02d} {case.title.replace('/', '-')}"
        for movement, source in enumerate(movements, start=1):
            name = f"{movement:02d} {MOVEMENTS[movement - 1]}.{case.ext}"
            target = folder / name
            args = tuple(ffmpeg_args(case, number, movement, source, target))
            jobs.append(Job(source, target, args, metadata(case, number, movement)))
    return jobs


# The tags that ffmpeg writes as iTunes atoms. "+use_metadata_tags" would write all of them as QuickTime keys,
# which Navidrome does not read: the files then show as unknown album and artist.
M4A_ATOMS = frozenset(("title", "album", "album_artist", "artist", "composer", "genre", "date", "disc", "track"))


def write_m4a_tags(path: pathlib.Path, tags: dict[str, str]) -> None:
    """Adds the tags without an iTunes atom (WORK, MOVEMENT) as free-form atoms."""
    audio = MP4(path)
    for key, value in tags.items():
        if key not in M4A_ATOMS:
            audio[f"----:com.apple.iTunes:{key}"] = [value.encode()]
    audio.save()


def write_wav_tags(path: pathlib.Path, tags: dict[str, str]) -> None:
    """ffmpeg's WAV muxer writes no ID3 chunk, so the lab adds one with the tags of the other cases."""
    audio = WAVE(path)
    if audio.tags is None:
        audio.add_tags()
    for key, value in tags.items():
        frame = ID3_FRAMES.get(key)
        audio.tags.add(frame(encoding=3, text=value) if frame else TXXX(encoding=3, desc=key, text=value))
    audio.save(v2_version=4)


def build(movements: tuple[pathlib.Path, pathlib.Path], out: pathlib.Path) -> int:
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found on PATH. Install it (Linux: apt install ffmpeg; macOS: brew install ffmpeg).")
    for path in movements:
        if not path.is_file():
            sys.exit(f"Source file not found: {path}")
    jobs = plan(movements, out)
    for job in jobs:
        job.target.parent.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(job.args, capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit(f"ffmpeg failed for {job.target.name}:\n{result.stderr.strip()}")
        if job.target.suffix == ".wav":
            write_wav_tags(job.target, job.tags)
        if job.target.suffix == ".m4a":
            write_m4a_tags(job.target, job.tags)
        print(job.target.relative_to(out))
    print(f"{len(jobs)} files, {len(CASES)} test cases in {out / ALBUM}")
    return len(jobs)


def lan_address() -> str:
    """The address of the interface that reaches the home network. Sends no packet."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(("192.0.2.1", 9))
            addr = probe.getsockname()[0]
        except OSError:
            sys.exit("No network address found. Join the home Wi-Fi or pass --address.")
    return home_address(addr)


def home_address(addr: str) -> str:
    """A detected address must be private: on a public one the server would be on the internet."""
    if not ipaddress.ip_address(addr).is_private:
        sys.exit(f"{addr} is not a private address. Join the home Wi-Fi, or pass --address with a private one.")
    return addr


def navidrome_asset(system: str, machine: str) -> str:
    arch = {"x86_64": "amd64", "amd64": "amd64", "aarch64": "arm64", "arm64": "arm64"}.get(machine.lower())
    if system not in ("Linux", "Darwin") or arch is None:
        sys.exit(f"No Navidrome build for {system} {machine}.")
    return f"navidrome_{NAVIDROME_VERSION}_{system.lower()}_{arch}.tar.gz"


def fetch_navidrome(work: pathlib.Path) -> pathlib.Path:
    binary = work / "navidrome"
    if binary.exists():
        return binary
    base = f"https://github.com/navidrome/navidrome/releases/download/v{NAVIDROME_VERSION}"
    asset = navidrome_asset(platform.system(), platform.machine())
    archive = work / asset
    urllib.request.urlretrieve(f"{base}/{asset}", archive)
    sums = urllib.request.urlopen(f"{base}/navidrome_checksums.txt").read().decode()
    expected = next((line.split()[0] for line in sums.splitlines() if line.endswith(asset)), None)
    if expected != hashlib.sha256(archive.read_bytes()).hexdigest():
        archive.unlink()
        sys.exit("Navidrome download does not match its published checksum.")
    with tarfile.open(archive) as tar:
        tar.extract("navidrome", work, filter="data")
    archive.unlink()
    binary.chmod(0o755)
    return binary


def password_change(flag: str | None, stored: str | None) -> bool:
    """True when a later run must set the lab user's password: the flag always wins over the stored one."""
    return flag is not None and stored is not None and flag != stored


def post_json(url: str, body: dict[str, object], headers: dict[str, str] | None = None, method: str = "POST") -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", **(headers or {})},
        method=method,
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read() or b"{}")


def change_password(base: str, current: str, new: str) -> None:
    """Sets the lab user's password through the server's own user API, signed in with the stored password."""
    try:
        login = post_json(f"{base}/auth/login", {"username": USER, "password": current})
        post_json(
            f"{base}/api/user/{login['id']}",
            {
                "id": login["id"],
                "userName": USER,
                "name": login.get("name", USER),
                "isAdmin": True,
                "password": new,
                "currentPassword": current,
            },
            {"X-ND-Authorization": f"Bearer {login['token']}"},
            method="PUT",
        )
    except (OSError, KeyError) as error:
        sys.exit(f"Navidrome did not accept the new password: {error}. Delete the work folder to start again.")


def serve(music: pathlib.Path, work: pathlib.Path, address: str, fixed: str | None = None) -> None:
    if not (music / ALBUM).is_dir():
        sys.exit(f"No lab library in {music}. Run build first.")
    work.mkdir(parents=True, exist_ok=True)
    binary = fetch_navidrome(work)
    secret = work / "password.txt"
    # The password file is written only after the admin exists, so a failed first run is retried as a first run.
    first_run = not secret.exists()
    stored = None if first_run else secret.read_text().strip()
    password = fixed or stored or secrets.token_urlsafe(12)
    env = {
        **os.environ,
        "ND_MUSICFOLDER": str(music),
        "ND_DATAFOLDER": str(work / "data"),
        "ND_ADDRESS": address,
        "ND_PORT": str(PORT),
        "ND_LOGLEVEL": "warn",
        "ND_ENABLEINSIGHTSCOLLECTOR": "false",
        "ND_ENABLESHARING": "false",
        "ND_ENABLETRANSCODINGCONFIG": "false",
        "ND_ENABLEDOWNLOADS": "false",
    }
    server = subprocess.Popen([str(binary)], env=env)
    base = f"http://{address}:{PORT}"
    try:
        up = False
        for _ in range(60):
            if server.poll() is not None:
                break
            try:
                urllib.request.urlopen(f"{base}/ping", timeout=2)
                up = True
                break
            except OSError:
                time.sleep(1)
        if not up:
            sys.exit(f"Navidrome did not start on {base}. Its messages are above; check that port {PORT} is free.")
        # The first call creates the admin; later runs get a refusal, which is fine.
        request = urllib.request.Request(
            f"{base}/auth/createAdmin",
            data=json.dumps({"username": USER, "password": password}).encode(),
            headers={"Content-Type": "application/json"},
        )
        try:
            urllib.request.urlopen(request, timeout=10)
        except urllib.error.HTTPError as error:
            if first_run:
                sys.exit(f"Navidrome did not create the admin user: HTTP {error.code}.")
        except OSError as error:
            sys.exit(f"Navidrome did not create the admin user: {error}")
        if password_change(fixed, stored):
            change_password(base, stored, password)
        if first_run or password_change(fixed, stored):
            secret.touch(mode=0o600)
            secret.write_text(password)
        print(f"\nNavidrome {NAVIDROME_VERSION} on {base}\nUser: {USER}\nPassword: {password}\nStop with Ctrl-C.")
        server.wait()
    except KeyboardInterrupt:
        pass
    finally:
        server.terminate()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    b = commands.add_parser("build", help="encode the test cases")
    b.add_argument("--movement1", type=pathlib.Path, required=True, help="source FLAC 24/96, movement 1")
    b.add_argument("--movement2", type=pathlib.Path, required=True, help="source FLAC 24/96, movement 2")
    b.add_argument("--out", type=pathlib.Path, default=pathlib.Path("lab-library"))
    s = commands.add_parser("serve", help="run Navidrome on the library, on the home network only")
    s.add_argument("--music", type=pathlib.Path, default=pathlib.Path("lab-library"))
    s.add_argument("--work", type=pathlib.Path, default=pathlib.Path("lab-server"), help="Navidrome binary and data")
    s.add_argument("--password", help="fixed password of user lab; replaces the stored one on a later run")
    s.add_argument("--address", help="address to bind; default is this machine's home network address")
    options = parser.parse_args()
    if options.command == "build":
        build((options.movement1, options.movement2), options.out)
    else:
        serve(options.music.resolve(), options.work.resolve(), options.address or lan_address(), options.password)


if __name__ == "__main__":
    main()
