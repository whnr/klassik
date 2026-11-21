"""Checks that every palette contrast failure reaches the report."""

import contextlib
import importlib.util
import io
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


if __name__ == "__main__":
    unittest.main()
