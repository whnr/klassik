"""Checks that every palette contrast failure and every dangling ADR number reaches the report."""

import contextlib
import importlib.util
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "design_check", Path(__file__).resolve().parents[1] / "design/scripts/check.py"
)
design_check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(design_check)


class ContrastTests(unittest.TestCase):
    def test_every_failed_pair_fails_the_check(self):
        pairs = {(room, fg, bg) for room in design_check.ROOMS for fg, bg, _ in design_check.pairs(room)}
        expected = len(design_check.ACCENTS) * len(pairs)
        with (
            patch.object(design_check, "ratio", return_value=1),
            patch.object(design_check, "KNOWN", pairs, create=True),
        ):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(design_check.main(), 1)
            self.assertEqual(output.getvalue().count("FAIL contrast:"), expected)


# The numbers are joined at run time so that this file holds no dangling reference itself.
GONE = ("00" + "44", "00" + "46", "00" + "08")


class MentionTests(unittest.TestCase):
    def mentioned(self, text, in_adr=False):
        return design_check.mentioned(text, in_adr)

    def test_contextual_bare_forms_are_found(self):
        a, b, c = GONE
        forms = {
            f"The retry rule is replaced by {a}.": {a},
            f"Replaces the rules of ADR {int(a)}.": {a},
            f"See the ADRs {a} and {b}.": {a, b},
            f"records {a} and {b} changed it": {a, b},
            f"as in the records {a}, {b} and {c}": {a, b, c},
            f"see {c}": {c},
            f"{a}-retry-rule.md": {a},
            f"ADR-{a} and ADR-{int(b)}": {a, b},
            f"see {a}-retry-rule": {a},
        }
        for text, expected in forms.items():
            self.assertEqual(self.mentioned(text), expected, text)

    def test_numbers_outside_an_adr_context_are_ignored(self):
        for text in (
            "Build 0044 shipped in 2026.",
            "Version 1.0.44, year 2026, 0.44 s",
            "timer 00:44",
            "Order 12044",
            "Builds 0043 and 0044 passed",
            "Upgrade from 0044 to 0045",
            "Newer than 0044",
            "Same as 0044",
        ):
            self.assertEqual(self.mentioned(text), set(), text)

    def test_inside_docs_adr_every_bare_number_counts_except_links_and_the_title(self):
        a, b, _ = GONE
        self.assertEqual(self.mentioned(f"# {a}. Title\n\nKeep {b} as is. [{a}]({a}-x.md)", True), {b, a})
        self.assertEqual(self.mentioned(f"# {a}. Title\n\n[0001](#top)", True), set())


class RepoTests(unittest.TestCase):
    def repo(self, files, records=("0001-a.md",)):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        (root / "docs/adr").mkdir(parents=True)
        for name in records:
            (root / "docs/adr" / name).write_text("# x\n")
        for name, data in files.items():
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            (root / name).write_bytes(data)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "add", "-A"], cwd=root, check=True)
        return root

    def test_dangling_bare_reference_fails(self):
        a = GONE[0]
        root = self.repo(
            {"docs/adr/0001-a.md": f"# 0001. A\n\nReplaced by {a}.\n".encode(), "x.md": f"see {a}".encode()}
        )
        self.assertEqual(
            design_check.check_mentions(root),
            [f"docs/adr/0001-a.md: ADR {a} does not exist", f"x.md: ADR {a} does not exist"],
        )

    def test_existing_record_and_plain_numbers_pass(self):
        root = self.repo({"x.md": b"see 0001, build 0044, ADR 1", "b.bin": b"\xff\xfe ADR " + GONE[0].encode()})
        self.assertEqual(design_check.check_mentions(root), [])

    def test_unreadable_tracked_file_fails(self):
        root = self.repo({"gone.swift": b"x", "locked.swift": b"x"})
        (root / "gone.swift").unlink()
        (root / "locked.swift").chmod(0)
        self.addCleanup((root / "locked.swift").chmod, 0o644)
        problems = design_check.check_mentions(root)
        self.assertEqual(len(problems), 1 if os.geteuid() == 0 else 2, problems)
        self.assertTrue(problems[0].startswith("gone.swift: cannot be read"))

    def test_read_error_is_reported(self):
        root = self.repo({"a.txt": b"x"})
        with patch.object(Path, "read_bytes", side_effect=PermissionError(13, "Permission denied")):
            self.assertIn("a.txt: cannot be read (Permission denied)", design_check.check_mentions(root))

    def test_empty_adr_inventory_fails(self):
        root = self.repo({"x.md": b"hello"}, records=())
        self.assertEqual(design_check.check_mentions(root), ["docs/adr: no ADR records found"])

    def test_vague_pointer_fails(self):
        root = self.repo(
            {
                "a.md": b"Replaces the rules of an earlier record.\n",
                "b.md": b"Contradicts the ADR on orders.\n",
                "c.md": b"The ADR table has rows. A deleted record is gone.\n",
                "ok.md": b"Replaces [0001](0001-a.md). Another recording plays.\n",
            }
        )
        self.assertEqual(
            design_check.check_vague(root),
            [
                "a.md:1: points to an ADR without naming it",
                "b.md:1: points to an ADR without naming it",
                "c.md:1: points to an ADR without naming it",
            ],
        )

    def test_specimen_tag_and_bead_fail(self):
        root = self.repo(
            {
                "a.swift": b"/// A style (design/specimen/tokens.html).\n",
                "b.md": b"Check it. (sz-abc1.2)\n",
                "ok.md": b"Run `unix:sz-codex`. The page tokens.html loads.\n",
                "ok.swift": b"/// A style of the token page.\n",
                "str.swift": b'let a = "(tokens.html)"\nlet u = "https://x.test/(tokens.html)"\n',
                "prose.swift": b"/// As work.html draws them, with css: tokens.css .a\n",
            }
        )
        self.assertEqual(
            design_check.check_tags(root),
            ["a.swift:1: a comment tags a specimen file", "b.md:1: a document names a bead"],
        )

    def test_specimen_tag_forms_fail(self):
        forms = {
            "bare.swift": "/// A style (tokens.html).",
            "path.swift": "/// A style (design/specimen/tokens.html).",
            "comma.swift": "/// A style (search.html, the sheet).",
            "class.swift": "/// The field (search.html .narrow).",
            "name.swift": "/// A row (person.html workRow).",
            "ticks.swift": "/// The kind in bold (search.html `.seg button.on`).",
            "caps.swift": "// Buttons beside the row (tokens.html SWIPE).",
            "lead.swift": "/// The wash (specimen player.html `.wash`).",
            "see.swift": "// Gaps above the title (see specimen.css `.page-head`).",
            "per.swift": "# Title and Done (per specimen.js K.sheet)",
            "from.swift": "/// The icon (from tokens.js ICON.chronology).",
            "html.html": "// Swipe Right opens Download (tokens.html SWIPE).",
        }
        root = self.repo({name: (text + "\n").encode() for name, text in forms.items()})
        self.assertEqual(
            design_check.check_tags(root),
            [f"{name}:1: a comment tags a specimen file" for name in sorted(forms)],
        )


if __name__ == "__main__":
    unittest.main()
