"""Tests for playback_lab.py: the folder plan, the ffmpeg arguments, and one real run when ffmpeg exists."""

import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

import playback_lab as lab

SRC = (pathlib.Path("/src/one.flac"), pathlib.Path("/src/two.flac"))
OUT = pathlib.Path("/out")


def option(args, name):
    return args[args.index(name) + 1]


class PlanTests(unittest.TestCase):
    def test_every_case_has_two_movements_in_its_own_folder(self):
        jobs = lab.plan(SRC, OUT)
        self.assertEqual(len(jobs), 2 * len(lab.CASES))
        folders = {job.target.parent for job in jobs}
        self.assertEqual(len(folders), len(lab.CASES))
        for folder in folders:
            self.assertEqual(folder.parent, OUT / lab.ALBUM)
            self.assertEqual(len([j for j in jobs if j.target.parent == folder]), 2)

    def test_movement_one_uses_the_first_source(self):
        for number, job in enumerate(lab.plan(SRC, OUT)):
            self.assertEqual(job.source, SRC[number % 2])
            self.assertTrue(job.target.name.startswith(f"{number % 2 + 1:02d} "))

    def test_case_list_matches_the_epic(self):
        self.assertEqual(
            [c.title for c in lab.CASES][:3],
            ["FLAC 24/96", "FLAC 16/44.1", "FLAC 24/192"],
        )
        self.assertEqual(len(lab.CASES), 12)
        self.assertEqual(len({c.slug for c in lab.CASES}), 12)

    def test_folder_names_are_unique_and_sort_in_case_order(self):
        names = sorted({job.target.parent.name for job in lab.plan(SRC, OUT)})

        self.assertTrue(all(re.match(r"\d\d ", n) for n in names))
        self.assertNotIn("/", "".join(names))


class ArgumentTests(unittest.TestCase):
    def args(self, slug, movement=1):
        case = next(c for c in lab.CASES if c.slug == slug)
        number = lab.CASES.index(case) + 1
        return lab.ffmpeg_args(case, number, movement, SRC[0], OUT / f"x.{case.ext}")

    def test_source_tags_and_video_are_dropped(self):
        args = self.args("flac-24-96")
        self.assertIn("-vn", args)
        self.assertEqual(option(args, "-map_metadata"), "-1")

    def test_flac_depth_and_rate(self):
        a = self.args("flac-24-96")
        self.assertEqual((option(a, "-sample_fmt"), option(a, "-ar")), ("s32", "96000"))
        self.assertEqual(option(a, "-bits_per_raw_sample"), "24")
        b = self.args("flac-16-44")
        self.assertEqual((option(b, "-sample_fmt"), option(b, "-ar")), ("s16", "44100"))
        self.assertEqual(option(self.args("flac-24-192"), "-ar"), "192000")

    def test_alac_uses_planar_formats(self):
        self.assertEqual(option(self.args("alac-24-96"), "-sample_fmt"), "s32p")
        self.assertEqual(option(self.args("alac-16-44"), "-sample_fmt"), "s16p")

    def test_mp3_header_switch(self):
        self.assertEqual(option(self.args("mp3-lame-header"), "-write_xing"), "1")
        self.assertEqual(option(self.args("mp3-no-header"), "-write_xing"), "0")

    def test_m4a_keeps_custom_tags(self):
        self.assertIn("+use_metadata_tags", self.args("aac-256"))
        self.assertNotIn("+use_metadata_tags", self.args("flac-24-96"))

    def test_rate_change_differs_per_movement(self):
        self.assertEqual(option(self.args("rate-change", 1), "-ar"), "96000")
        self.assertEqual(option(self.args("rate-change", 2), "-ar"), "44100")

    def test_tags_group_the_movements_as_one_work(self):
        tags = {}
        for movement in (1, 2):
            args = self.args("wav", movement)
            tags[movement] = dict(a.split("=", 1) for a in args if re.match(r"^[a-z_]+=", a))
        self.assertEqual(tags[1]["work"], tags[2]["work"])
        self.assertEqual(tags[1]["album"], tags[2]["album"])
        self.assertEqual(tags[1]["disc"], tags[2]["disc"])
        self.assertEqual((tags[1]["movement"], tags[2]["movement"]), ("1", "2"))
        self.assertEqual(tags[1]["movementtotal"], "2")

    def test_discs_differ_between_cases(self):
        discs = {lab.metadata(c, n, 1)["disc"] for n, c in enumerate(lab.CASES, start=1)}
        self.assertEqual(len(discs), len(lab.CASES))

    def test_replaygain_only_on_some_cases(self):
        with_rg = [c.slug for c in lab.CASES if c.tags]
        self.assertTrue(0 < len(with_rg) < len(lab.CASES))
        self.assertIn("replaygain_track_gain", lab.metadata(lab.CASES[0], 1, 1))


class BuildTests(unittest.TestCase):
    def test_missing_ffmpeg_exits_before_writing_anything(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out"
            with mock.patch.object(lab.shutil, "which", return_value=None):
                with self.assertRaises(SystemExit) as caught:
                    lab.build(SRC, out)
            message = str(caught.exception.code)
            self.assertIn("ffmpeg not found", message)
            self.assertNotIn("\n", message)
            self.assertFalse(out.exists())

    def test_missing_source_exits_before_writing_anything(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out"
            with mock.patch.object(lab.shutil, "which", return_value="/usr/bin/ffmpeg"):
                with self.assertRaises(SystemExit) as caught:
                    lab.build(SRC, out)
            self.assertEqual(str(caught.exception.code), "Source file not found: /src/one.flac")
            self.assertFalse(out.exists())


class AddressTests(unittest.TestCase):
    def test_home_address_is_accepted(self):
        self.assertEqual(lab.home_address("192.168.1.20"), "192.168.1.20")

    def test_public_address_is_refused(self):
        with self.assertRaises(SystemExit):
            lab.home_address("8.8.8.8")


class ServerTests(unittest.TestCase):
    def test_asset_names(self):
        self.assertEqual(
            lab.navidrome_asset("Linux", "x86_64"), f"navidrome_{lab.NAVIDROME_VERSION}_linux_amd64.tar.gz"
        )
        self.assertEqual(
            lab.navidrome_asset("Darwin", "arm64"), f"navidrome_{lab.NAVIDROME_VERSION}_darwin_arm64.tar.gz"
        )
        with self.assertRaises(SystemExit):
            lab.navidrome_asset("Windows", "AMD64")


# ffmpeg -i audio line per movement. The codec may carry a decoder name in brackets, which differs by ffmpeg build.
AUDIO = {
    1: (r"Audio: flac[^\n]*, 96000 Hz, stereo, s32 \(24 bit\)",) * 2,
    2: (r"Audio: flac[^\n]*, 44100 Hz, stereo, s16\b",) * 2,
    3: (r"Audio: flac[^\n]*, 192000 Hz, stereo, s32 \(24 bit\)",) * 2,
    4: (r"Audio: alac[^\n]*, 96000 Hz, stereo, s32p \(24 bit\)",) * 2,
    5: (r"Audio: alac[^\n]*, 44100 Hz, stereo, s16p",) * 2,
    6: (r"Audio: aac[^\n]*, 44100 Hz",) * 2,
    7: (r"Audio: mp3[^\n]*, 44100 Hz",) * 2,
    8: (r"Audio: mp3[^\n]*, 44100 Hz",) * 2,
    9: (r"Audio: pcm_s24le[^\n]*, 96000 Hz, stereo, s32 \(24 bit\)",) * 2,
    10: (r"Audio: pcm_s24be[^\n]*, 96000 Hz[^\n]*s32 \(24 bit\)",) * 2,
    11: (r"Audio: opus[^\n]*, 48000 Hz",) * 2,
    12: (
        r"Audio: flac[^\n]*, 96000 Hz, stereo, s32 \(24 bit\)",
        r"Audio: flac[^\n]*, 44100 Hz, stereo, s32 \(24 bit\)",
    ),
}


@unittest.skipUnless(shutil.which("ffmpeg"), "needs ffmpeg")
class EndToEndTests(unittest.TestCase):
    def tone(self, path, freq):
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", f"sine=f={freq}:r=96000:d=1.5",
             "-ac", "2", "-c:a", "flac", "-sample_fmt", "s32", "-bits_per_raw_sample", "24", str(path)],
            check=True,
        )  # fmt: skip

    def info(self, path):
        result = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(path)], capture_output=True, text=True)
        return result.stderr

    def test_builds_every_case(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            one, two = tmp / "one.flac", tmp / "two.flac"
            self.tone(one, 440)
            self.tone(two, 660)
            count = lab.build((one, two), tmp / "out")
            self.assertEqual(count, 2 * len(lab.CASES))
            files = sorted(f for f in (tmp / "out" / lab.ALBUM).rglob("*") if f.is_file())
            self.assertEqual(len(files), count)
            for f in files:
                number = int(f.parent.name[:2])
                movement = int(f.name[:2])
                case = lab.CASES[number - 1]
                info = self.info(f)
                data = f.read_bytes()
                self.assertRegex(info, AUDIO[number][movement - 1], f.name)
                # ffmpeg's WAV muxer writes no ID3 chunk, so WAV files carry no WORK; Navidrome groups them by album.
                if number != 9:
                    self.assertRegex(info, rf"work\s*:\s*{re.escape(case.title)}", f.name)
                if number == 6:
                    self.assertIn(b"elst", data, "AAC needs the encoder delay edit list")
                if number == 7:
                    self.assertTrue(b"Xing" in data or b"Info" in data, "LAME header missing")
                if number == 8:
                    self.assertFalse(b"Xing" in data or b"Info" in data, "MP3 has a header it should not have")

if __name__ == "__main__":
    unittest.main()
