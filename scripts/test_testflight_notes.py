"""Check the narrow boundary between tester notes and development instructions."""

import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

from testflight_notes import previous_notes, validate


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

    def test_bead_id_fails(self):
        with self.assertRaisesRegex(ValueError, "bead ID"):
            validate("Klassik 0.10.4\n\n- Play. Expect sound. (sz-abc1)", "0.10.4")

    def test_words_containing_development_terms_pass(self):
        notes = "Klassik 0.10.4\n\n- Search for Circle, Branching, and Reposition. Expect matching recordings."
        self.assertEqual(validate(notes, "0.10.4"), notes)

    def test_published_app_checks_pass(self):
        root = pathlib.Path(__file__).resolve().parent.parent
        notes = (root / "docs/what-to-test.md").read_text().strip()
        version = notes.splitlines()[0].removeprefix("Klassik ")
        self.assertEqual(validate(notes, version), notes)

    def test_numbered_checklist_fails(self):
        with self.assertRaisesRegex(ValueError, "numbered checks"):
            validate("Klassik 0.10.4\n\n1. Play. Expect sound.", "0.10.4")

    def test_long_summary_fails(self):
        with self.assertRaisesRegex(ValueError, "words"):
            validate("Klassik 0.10.4\n\n- " + "word " * 151, "0.10.4")
        validate("Klassik 0.10.4\n\n- " + "word " * 149, "0.10.4")

    def test_repeating_the_last_release_fails(self):
        old = "Klassik 0.10.3\n\n- Page menu on work pages.\n- Search shows nicknames."
        with self.assertRaisesRegex(ValueError, "repeats"):
            validate("Klassik 0.10.4\n\n- Search shows nicknames.\n- Player closes by drag.", "0.10.4", old)
        validate("Klassik 0.10.4\n\n- Player closes by drag.", "0.10.4", old)

    def test_empty_summary_fails(self):
        for notes in ("Klassik 0.10.4", "Klassik 0.10.4\n", "Klassik 0.10.4\n\n  \n"):
            with self.subTest(notes=notes):
                with self.assertRaisesRegex(ValueError, "no summary"):
                    validate(notes, "0.10.4")

    def test_version_mismatch_fails(self):
        with self.assertRaisesRegex(ValueError, "must start"):
            validate("Klassik 0.10.3\n\n- Play. Expect sound.", "0.10.4")

    def test_length_limit(self):
        notes = "Klassik 0.10.4\n".ljust(4000, "a")
        self.assertEqual(validate(notes, "0.10.4"), notes)
        with self.assertRaisesRegex(ValueError, "4001 characters"):
            validate(notes + "a", "0.10.4")

    def test_check_needs_no_upload_dependencies(self):
        script = pathlib.Path(__file__).with_name("testflight_notes.py")
        result = subprocess.run([sys.executable, "-S", str(script), "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def make_repo(self, tag=None):
        directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, directory)

        def run(*args):
            subprocess.run(["git", "-C", directory, *args], check=True, capture_output=True)

        run("init", "-q")
        run("config", "user.email", "t@example.com")
        run("config", "user.name", "t")
        pathlib.Path(directory, "docs").mkdir()
        pathlib.Path(directory, "docs/what-to-test.md").write_text("Klassik 0.10.3\n\n- Old line.\n")
        run("add", ".")
        run("commit", "-q", "-m", "notes")
        if tag:
            run("tag", tag)
        return directory

    def test_previous_notes_without_tags_fails(self):
        with self.assertRaisesRegex(ValueError, "No v\\* release tag"):
            previous_notes(self.make_repo(), "0.10.4")

    def test_previous_notes_unreadable_file_fails(self):
        directory = self.make_repo("v0.10.3")
        subprocess.run(["git", "-C", directory, "rm", "-q", "docs/what-to-test.md"], check=True)
        subprocess.run(["git", "-C", directory, "commit", "-q", "-m", "drop"], check=True)
        subprocess.run(["git", "-C", directory, "tag", "v0.10.3.1"], check=True)
        with self.assertRaisesRegex(ValueError, "Cannot read"):
            previous_notes(directory, "0.10.4")

    def test_previous_notes_git_failure_fails(self):
        with self.assertRaisesRegex(ValueError, "Cannot list release tags"):
            previous_notes(pathlib.Path(tempfile.gettempdir(), "no-such-repo-dir"), "0.10.4")

    def test_previous_notes_reads_newest_tag(self):
        self.assertIn("Old line", previous_notes(self.make_repo("v0.10.3"), "0.10.4"))

    def test_previous_notes_tagged_version_skips(self):
        self.assertIsNone(previous_notes(self.make_repo("v0.10.4"), "0.10.4"))


if __name__ == "__main__":
    unittest.main()
