# /// script
# requires-python = ">=3.12"
# dependencies = ["pyjwt[crypto]"]
# ///
"""Crash exports must contain evidence, and failed writes must fail the run."""

import contextlib
import io
import pathlib
import tempfile
import unittest
from unittest.mock import patch

from testflight_feedback import export_crash


class CrashExportTests(unittest.TestCase):
    item = {"id": "fixture", "attributes": {"createdDate": "2026-11-17T10:20:30Z"}}

    def export(self, attributes, out):
        with patch("testflight_feedback.get", return_value={"data": {"attributes": attributes}}):
            export_crash(self.item, out)

    def test_empty_logs_create_no_artifact(self):
        for attributes in ({}, {"logText": None}, {"logText": ""}, {"logText": " \n\t"}):
            with self.subTest(attributes=attributes), tempfile.TemporaryDirectory() as folder:
                out = pathlib.Path(folder)
                self.export(attributes, out)
                self.assertEqual(list(out.iterdir()), [])

    def test_full_log_survives_export(self):
        log = "\n".join(f"Thread {index}: fixture é" for index in range(150))
        with tempfile.TemporaryDirectory() as folder:
            out = pathlib.Path(folder)
            self.export({"logText": log}, out)
            files = list(out.iterdir())
            self.assertEqual([file.name for file in files], ["2026-11-17T102030-fixture.crash"])
            self.assertEqual(files[0].read_text(encoding="utf-8"), log)

    def test_write_failure_propagates_without_success_message(self):
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()) as output:
            with patch.object(pathlib.Path, "write_text", side_effect=OSError("disk full")):
                with self.assertRaisesRegex(OSError, "disk full"):
                    self.export({"logText": "Thread 1: fixture"}, pathlib.Path(folder))
            self.assertNotIn("crash log: ", output.getvalue())

    def test_unprocessed_log_creates_no_artifact(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch("testflight_feedback.get", side_effect=RuntimeError("not processed")):
                export_crash(self.item, pathlib.Path(folder))
            self.assertEqual(list(pathlib.Path(folder).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
