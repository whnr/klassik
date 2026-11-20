"""Tests for the TestFlight gate: python3 -m unittest discover -s scripts -p "test_green_test_gate.py"."""

import pathlib
import subprocess
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import green_test_gate  # noqa: E402


class IgnoredTests(unittest.TestCase):
    def test_documentation_paths(self):
        for path in ("README.md", "docs/adr/0001.md", "docs/agents/x.png", "design/notes.md", "LICENSE"):
            self.assertTrue(green_test_gate.is_ignored(path), path)

    def test_code_paths(self):
        for path in ("Klassik/App.swift", "docs.py", "scripts/docs/x.py", "LICENSE.txt", ".github/workflows/test.yml"):
            self.assertFalse(green_test_gate.is_ignored(path), path)


class CoveringTests(unittest.TestCase):
    def find(self, commits, changes, green):
        return green_test_gate.covering(commits, lambda sha: changes[sha], lambda sha: sha in green)

    def test_the_commit_itself_is_green(self):
        self.assertEqual(self.find(["c", "b"], {"c": ["a.swift"]}, {"c"}), ("c", None))

    def test_docs_only_commits_fall_back_to_a_green_ancestor(self):
        changes = {"c": ["README.md"], "b": ["docs/x.md"], "a": ["a.swift"]}
        self.assertEqual(self.find(["c", "b", "a"], changes, {"a"}), ("a", None))

    def test_a_code_change_without_a_run_is_not_covered(self):
        changes = {"c": ["README.md"], "b": ["a.swift"], "a": []}
        sha, reason = self.find(["c", "b", "a"], changes, {"a"})
        self.assertIsNone(sha)
        self.assertIn("no green Test run for b", reason)

    def test_no_green_run_in_reach(self):
        sha, reason = self.find(["c"], {"c": ["README.md"]}, set())
        self.assertIsNone(sha)
        self.assertIn("last 1 commits", reason)

    def test_real_diff_tree_output_has_no_empty_path(self):
        out = subprocess.run(
            ["git", "diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", "HEAD"],
            stdout=subprocess.PIPE,
            text=True,
            check=True,
            cwd=pathlib.Path(__file__).parent,
        ).stdout
        self.assertTrue(out.endswith("\n"))
        self.assertNotIn("", green_test_gate.parse_paths(out))

    def test_parse_paths_drops_the_trailing_newline(self):
        self.assertEqual(green_test_gate.parse_paths("docs/x.md\nREADME.md\n"), ["docs/x.md", "README.md"])
        self.assertEqual(green_test_gate.parse_paths(""), [])
        changes = {"c": green_test_gate.parse_paths("docs/x.md\n"), "a": []}
        self.assertEqual(green_test_gate.covering(["c", "a"], changes.get, lambda s: s == "a"), ("a", None))


if __name__ == "__main__":
    unittest.main()
