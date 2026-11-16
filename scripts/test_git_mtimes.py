"""Checks that cached builds see source changes committed during a merge."""

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("git_mtimes.py").resolve()


class MergeTimestampTests(unittest.TestCase):
    def test_merge_changes_receive_the_merge_time(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            env = os.environ | {
                "GIT_AUTHOR_NAME": "Fixture",
                "GIT_AUTHOR_EMAIL": "fixture@example.org",
                "GIT_COMMITTER_NAME": "Fixture",
                "GIT_COMMITTER_EMAIL": "fixture@example.org",
            }

            def git(*args, timestamp=1_000_000_000):
                dated = env | {
                    "GIT_AUTHOR_DATE": f"@{timestamp} +0000",
                    "GIT_COMMITTER_DATE": f"@{timestamp} +0000",
                }
                subprocess.run(["git", *args], cwd=root, env=dated, capture_output=True, check=True)

            git("init", "-b", "main")
            source = root / "source.swift"
            source.write_text("initial\n")
            git("add", ".")
            git("commit", "-m", "Initial")
            git("checkout", "-b", "topic")
            (root / "topic.swift").write_text("topic\n")
            git("add", ".")
            git("commit", "-m", "Topic", timestamp=1_000_000_100)
            git("checkout", "main")
            unchanged = root / "main.swift"
            unchanged.write_text("main\n")
            git("add", ".")
            git("commit", "-m", "Main", timestamp=1_000_000_200)
            git("merge", "--no-ff", "--no-commit", "topic")
            source.write_text("merge change\n")
            git("add", ".")
            git("commit", "-m", "Merge", timestamp=1_000_000_300)

            subprocess.run([sys.executable, str(SCRIPT)], cwd=root, capture_output=True, check=True)

            self.assertEqual(source.stat().st_mtime, 1_000_000_300)
            self.assertEqual(unchanged.stat().st_mtime, 1_000_000_200)


if __name__ == "__main__":
    unittest.main()
