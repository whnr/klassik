"""Check the narrow boundary between tester notes and development instructions."""

import pathlib
import subprocess
import sys
import unittest

from testflight_notes import validate


class NotesTests(unittest.TestCase):
    def test_development_instructions_fail(self):
        cases = (
            "Wait for CI to pass.",
            "Start the release workflow.",
            "Check the workflows before upload.",
            "Open GitHub and read the checks.",
            "Create a token for signing.",
            "Rotate tokens before release.",
            "Add the secret to the environment.",
            "Check the secrets before upload.",
            "Read AGENTS.md before testing.",
            "Read README for setup.",
            "Clone the repository.",
            "Check both repositories.",
            "Clone the repo. Expect a local checkout.",
            "Clone both repos.",
            "Push the release branch.",
            "Compare the branches.",
            "Approve the pull request.",
            "Read both pull requests.",
            "Build with Xcode.",
        )
        for instruction in cases:
            with self.subTest(instruction=instruction):
                with self.assertRaisesRegex(ValueError, "Development term"):
                    validate(f"Klassik 0.10.4\n\n- {instruction}", "0.10.4")
                with self.assertRaisesRegex(ValueError, "Development term"):
                    validate(f"Klassik 0.10.4\n\n- {instruction.swapcase()}", "0.10.4")

    def test_installed_app_actions_pass(self):
        cases = (
            "Open Settings. Set the server address. Expect the library to sync.",
            "Play a recording. Lock the phone. Expect playback to continue.",
            "Queue another recording. Expect playback to continue after the final movement.",
            "Open Search. Add a genre condition. Expect matching recordings.",
            "Open an album. Expect each performer name once, in track order.",
            "Play, pause, close Klassik, reopen, tap the mini player cover. "
            "Expect the same movement. Resume; expect matching audio.",
            "Open Classical Albums and remember an album name. Open a work, then return. Expect the same album name.",
            "Swipe an album, Play Next. Finish the current recording. Expect all tracks of that album in disc order.",
        )
        for instruction in cases:
            with self.subTest(instruction=instruction):
                notes = f"Klassik 0.10.4\n\n- {instruction}"
                self.assertEqual(validate(notes, "0.10.4"), notes)

    def test_words_containing_development_terms_pass(self):
        notes = "Klassik 0.10.4\n\n- Search for Circle, Branching, and Reposition. Expect matching recordings."
        self.assertEqual(validate(notes, "0.10.4"), notes)

    def test_published_app_checks_pass(self):
        root = pathlib.Path(__file__).resolve().parent.parent
        notes = (root / "docs/what-to-test.md").read_text().strip()
        version = notes.splitlines()[0].removeprefix("Klassik ")
        self.assertEqual(validate(notes, version), notes)

    def test_version_mismatch_fails(self):
        with self.assertRaisesRegex(ValueError, "must start"):
            validate("Klassik 0.10.3\n\n- Play.", "0.10.4")

    def test_length_limits(self):
        header = "Klassik 0.10.4\n\n"
        ok = header + "\n".join(["- " + " ".join(["word"] * 20)] * 7)
        self.assertEqual(validate(ok, "0.10.4"), ok)
        with self.assertRaisesRegex(ValueError, "26 words"):
            validate(header + "- " + " ".join(["word"] * 26), "0.10.4")
        with self.assertRaisesRegex(ValueError, "words; the limit is 150"):
            validate(header + "\n".join(["- " + " ".join(["word"] * 20)] * 8), "0.10.4")

    def test_format_and_bead_ids_fail(self):
        with self.assertRaisesRegex(ValueError, "Not a bullet"):
            validate("Klassik 0.10.4\n\n1. Play. Expect sound.", "0.10.4")
        with self.assertRaisesRegex(ValueError, "no bullets"):
            validate("Klassik 0.10.4\n", "0.10.4")
        with self.assertRaisesRegex(ValueError, "bead id"):
            validate("Klassik 0.10.4\n\n- Play sound. (sz-rs30.1.125.1)", "0.10.4")

    def test_check_needs_no_upload_dependencies(self):
        script = pathlib.Path(__file__).with_name("testflight_notes.py")
        result = subprocess.run([sys.executable, "-S", str(script), "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
