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
                    validate(f"Klassik 0.10.4\n\n1. {instruction}", "0.10.4")
                with self.assertRaisesRegex(ValueError, "Development term"):
                    validate(f"Klassik 0.10.4\n\n1. {instruction.swapcase()}", "0.10.4")

    def test_installed_app_actions_pass(self):
        cases = (
            "Open Settings. Set the server address. Expect the library to sync.",
            "Play a recording. Lock the phone. Expect playback to continue.",
            "Queue another recording. Expect playback to continue after the final movement.",
            "Open Search. Add a genre condition. Expect matching recordings.",
            "Open an album. Expect each performer name once, in track order.",
        )
        for instruction in cases:
            with self.subTest(instruction=instruction):
                notes = f"Klassik 0.10.4\n\n1. {instruction} (sz-iq9v)"
                self.assertEqual(validate(notes, "0.10.4"), notes)

    def test_words_containing_development_terms_pass(self):
        notes = "Klassik 0.10.4\n\n1. Search for Circle, Branching, and Reposition. Expect matching recordings."
        self.assertEqual(validate(notes, "0.10.4"), notes)

    def test_published_app_checks_pass(self):
        root = pathlib.Path(__file__).resolve().parent.parent
        notes = (root / "docs/what-to-test.md").read_text().strip()
        version = notes.splitlines()[0].removeprefix("Klassik ")
        self.assertEqual(validate(notes, version), notes)

    def test_version_mismatch_fails(self):
        with self.assertRaisesRegex(ValueError, "must start"):
            validate("Klassik 0.10.3\n\n1. Play. Expect sound.", "0.10.4")

    def test_length_limit(self):
        notes = "Klassik 0.10.4\n".ljust(4000, "a")
        self.assertEqual(validate(notes, "0.10.4"), notes)
        with self.assertRaisesRegex(ValueError, "4001 characters"):
            validate(notes + "a", "0.10.4")

    def test_check_needs_no_upload_dependencies(self):
        script = pathlib.Path(__file__).with_name("testflight_notes.py")
        result = subprocess.run([sys.executable, "-S", str(script), "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
