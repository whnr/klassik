"""Tests for the TestFlight gate: python3 -m unittest discover -s scripts -p "test_green_test_gate.py"."""

import contextlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import green_test_gate  # noqa: E402


class IgnoredTests(unittest.TestCase):
    def test_documentation_paths(self):
        for path in ("README.md", "docs/adr/0001.md", "docs/agents/x.png", "design/notes.md", "LICENSE"):
            self.assertTrue(green_test_gate.is_ignored(path), path)

    def test_code_paths(self):
        for path in ("Klassik/App.swift", "docs.py", "scripts/docs/x.py", "LICENSE.txt", ".github/workflows/test.yml"):
            self.assertFalse(green_test_gate.is_ignored(path), path)


def no_version_diff(sha):
    raise AssertionError(f"read the project.yml patch of {sha}")


class CoveringTests(unittest.TestCase):
    def find(self, commits, changes, green):
        return green_test_gate.covering(commits, lambda sha: changes[sha], lambda sha: sha in green, no_version_diff)

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
        # A scratch repo, because a CI checkout can be shallow and then diff-tree prints nothing.
        with tempfile.TemporaryDirectory() as tmp:

            def git(*args):
                return subprocess.run(
                    ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                    stdout=subprocess.PIPE,
                    text=True,
                    check=True,
                    cwd=tmp,
                ).stdout

            git("init", "-q")
            pathlib.Path(tmp, "README.md").write_text("x")
            git("add", "README.md")
            git("commit", "-q", "-m", "c")
            out = git("diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", "--root", "HEAD")
        self.assertTrue(out.endswith("\n"))
        self.assertEqual(green_test_gate.parse_paths(out), ["README.md"])

    def test_parse_paths_drops_the_trailing_newline(self):
        self.assertEqual(green_test_gate.parse_paths("docs/x.md\nREADME.md\n"), ["docs/x.md", "README.md"])
        self.assertEqual(green_test_gate.parse_paths(""), [])
        changes = {"c": green_test_gate.parse_paths("docs/x.md\n"), "a": []}
        found = green_test_gate.covering(["c", "a"], changes.get, lambda s: s == "a", no_version_diff)
        self.assertEqual(found, ("a", None))


PROJECT = """name: Klassik
settings:
  base:
    MARKETING_VERSION: "0.16.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  Klassik:
    type: application
    dependencies:
      - target: TaskRegistry
    settings:
      base:
        SWIFT_VERSION: "6.0"
"""


class History:
    """A scratch repo, because a CI checkout can be shallow and then diff-tree prints nothing."""

    def __init__(self, tmp):
        self.tmp = pathlib.Path(tmp)
        self.git("init", "-q", "-b", "main")

    def git(self, *args):
        return subprocess.run(
            ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
            stdout=subprocess.PIPE,
            text=True,
            check=True,
            cwd=self.tmp,
        ).stdout

    def commit(self, files, message="c"):
        for name, text in files.items():
            path = self.tmp / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD").strip()

    def find(self, green):
        head = self.git("rev-parse", "HEAD").strip()
        return green_test_gate.covering(
            green_test_gate.commits_from(head, cwd=self.tmp),
            lambda sha: green_test_gate.changed(sha, cwd=self.tmp),
            lambda sha: sha in green,
            lambda sha: green_test_gate.version_diff(sha, cwd=self.tmp),
        )


def bump(version="0.16.1", build="1"):
    return PROJECT.replace('"0.16.0"', f'"{version}"').replace('VERSION: "1"', f'VERSION: "{build}"')


class ReleaseHistoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = History(self.tmp.name)
        self.root = self.repo.commit({"project.yml": PROJECT, "Klassik/App.swift": "a"})
        self.green = self.repo.commit({"Klassik/App.swift": "b"})

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_release_commit_reuses_the_green_parent(self):
        self.repo.commit({"project.yml": bump(), "docs/what-to-test.md": "# 0.16.1"})
        self.assertEqual(self.repo.find({self.green}), (self.green, None))

    def test_both_version_lines_and_a_docs_commit_on_top(self):
        self.repo.commit({"project.yml": bump("0.17.0", "2"), "docs/what-to-test.md": "# 0.17.0"})
        self.repo.commit({"README.md": "x"})
        self.assertEqual(self.repo.find({self.green}), (self.green, None))

    def test_a_merge_commit_of_a_release_branch(self):
        self.repo.git("checkout", "-q", "-b", "release")
        self.repo.commit({"project.yml": bump(), "docs/what-to-test.md": "# 0.16.1"})
        self.repo.git("checkout", "-q", "main")
        self.repo.git("-c", "user.name=t", "-c", "user.email=t@t", "merge", "-q", "--no-ff", "-m", "m", "release")
        self.assertEqual(self.repo.find({self.green}), (self.green, None))

    def test_a_project_change_that_is_not_the_version_fails_closed(self):
        sha = self.repo.commit({"project.yml": bump().replace('"6.0"', '"6.2"')})
        found, reason = self.repo.find({self.green})
        self.assertIsNone(found)
        self.assertIn(f"no green Test run for {sha}", reason)
        self.assertIn("project.yml", reason)

    def test_a_new_project_line_fails_closed(self):
        self.repo.commit({"project.yml": bump() + "options:\n  bundleIdPrefix: x\n"})
        self.assertIsNone(self.repo.find({self.green})[0])

    def test_a_version_commit_with_code_fails_closed(self):
        self.repo.commit({"project.yml": bump(), "Klassik/App.swift": "c"})
        found, reason = self.repo.find({self.green})
        self.assertIsNone(found)
        self.assertIn("Klassik/App.swift", reason)

    def test_a_version_line_that_is_not_a_number_fails_closed(self):
        self.repo.commit({"project.yml": PROJECT.replace('"0.16.0"', '"$(BUILD)"')})
        self.assertIsNone(self.repo.find({self.green})[0])

    def test_a_mode_change_fails_closed(self):
        (self.repo.tmp / "project.yml").chmod(0o755)
        self.repo.git("add", "-A")
        self.repo.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "mode")
        self.assertIsNone(self.repo.find({self.green})[0])

    def test_one_quote_lines_around_a_dependency_fail_closed(self):
        # In YAML the open quote takes in every line up to the close quote, so the target loses its dependency.
        attack = PROJECT.replace(
            "    dependencies:\n      - target: TaskRegistry\n",
            '    MARKETING_VERSION: "1\n    dependencies:\n      - target: TaskRegistry\n    MARKETING_VERSION: 1"\n',
        )
        sha = self.repo.commit({"project.yml": attack, "docs/what-to-test.md": "# 0.16.1"})
        found, reason = self.repo.find({self.green})
        self.assertIsNone(found)
        self.assertIn(f"no green Test run for {sha}", reason)

    def test_an_added_version_line_fails_closed(self):
        self.repo.commit(
            {"project.yml": PROJECT.replace("      base:\n", '      base:\n        MARKETING_VERSION: "9"\n')}
        )
        self.assertIsNone(self.repo.find({self.green})[0])

    def test_a_removed_version_line_fails_closed(self):
        self.repo.commit({"project.yml": PROJECT.replace('    CURRENT_PROJECT_VERSION: "1"\n', "")})
        self.assertIsNone(self.repo.find({self.green})[0])

    def test_a_version_line_that_moves_fails_closed(self):
        line = '    CURRENT_PROJECT_VERSION: "1"\n'
        self.repo.commit({"project.yml": PROJECT.replace(line, "").replace("  base:\n", "  base:\n" + line, 1)})
        self.assertIsNone(self.repo.find({self.green})[0])

    def test_a_root_commit_fails_closed(self):
        self.assertIsNone(self.repo.find(set())[0])


class VersionOnlyTests(unittest.TestCase):
    HEAD = "diff --git a/project.yml b/project.yml\nindex 1..2 100644\n--- a/project.yml\n+++ b/project.yml\n"

    def test_version_lines(self):
        for body in (
            '@@ -9 +9 @@\n-    MARKETING_VERSION: "0.16.0"\n+    MARKETING_VERSION: "0.16.1"\n',
            '@@ -9,2 +9,2 @@\n-  MARKETING_VERSION: "0.16.0"\n-  CURRENT_PROJECT_VERSION: 1\n'
            '+  MARKETING_VERSION: "0.17.0"\n+  CURRENT_PROJECT_VERSION: 2\n',
            "@@ -4 +4 @@ x\n-  MARKETING_VERSION: 1\n+  MARKETING_VERSION: 2\n"
            "@@ -9 +9 @@\n-  CURRENT_PROJECT_VERSION: 1\n+  CURRENT_PROJECT_VERSION: 2\n",
        ):
            with self.subTest(body=body):
                self.assertTrue(green_test_gate.version_only(self.HEAD + body))

    def test_rejects(self):
        for diff in (
            "",
            self.HEAD,
            self.HEAD + "@@ -1 +1 @@\n----\n+---\n",
            self.HEAD + '@@ -9 +9 @@\n-    MARKETING_VERSION: "0.16.0"\n+    MARKETING_VERSION: "0.16.1" # x\n',
            self.HEAD + '@@ -9 +9 @@\n+    MARKETING_VERSION: "0.16.1"\n\\ No newline at end of file\n',
            "diff --git a/project.yml b/project.yml\nold mode 100644\nnew mode 100755\n",
            self.HEAD + '@@ -15,0 +16 @@\n+    MARKETING_VERSION: "1\n@@ -17,0 +19 @@\n+    MARKETING_VERSION: 1"\n',
            self.HEAD + '@@ -9 +9 @@\n-    MARKETING_VERSION: "0.16.0"\n+    MARKETING_VERSION: "1\n',
            self.HEAD + '@@ -9 +9 @@\n-    MARKETING_VERSION: "0.16.0"\n+    MARKETING_VERSION: 1"\n',
            self.HEAD + '@@ -9 +9 @@\n-    MARKETING_VERSION: "0.16.0"\n+      MARKETING_VERSION: "0.16.1"\n',
            self.HEAD + '@@ -9 +9 @@\n-    MARKETING_VERSION: "0.16.0"\n+    CURRENT_PROJECT_VERSION: "2"\n',
            self.HEAD + '@@ -9 +10 @@\n-    MARKETING_VERSION: "0.16.0"\n+    MARKETING_VERSION: "0.16.1"\n',
            self.HEAD + '@@ -9,2 +9 @@\n-    MARKETING_VERSION: "0.16.0"\n-    CURRENT_PROJECT_VERSION: "1"\n'
            '+    MARKETING_VERSION: "0.16.1"\n',
            self.HEAD + '@@ -9 +9 @@\n-    MARKETING_VERSION: "0.16.0"\n',
            self.HEAD + '@@ -9 +9 @@\n+    MARKETING_VERSION: "0.16.1"\n-    MARKETING_VERSION: "0.16.0"\n',
            "diff --git a/project.yml b/project.yml\ndeleted file mode 100644\n" + self.HEAD[40:],
        ):
            with self.subTest(diff=diff):
                self.assertFalse(green_test_gate.version_only(diff))


def merge(repo, branch, message="m"):
    repo.git("merge", "-q", "--no-ff", "-m", message, branch)
    return repo.git("rev-parse", "HEAD").strip()


class MergedHeadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = History(self.tmp.name)
        self.base = self.repo.commit({"Klassik/App.swift": "a", "Klassik/Other.swift": "a"})
        self.repo.git("checkout", "-q", "-b", "feature")
        self.head = self.repo.commit({"Klassik/App.swift": "b"})
        self.repo.git("checkout", "-q", "main")

    def tearDown(self):
        self.tmp.cleanup()

    def merged(self, sha):
        return green_test_gate.merged_head(sha, cwd=self.repo.tmp)

    def test_a_merge_of_an_up_to_date_head_is_that_head(self):
        self.assertEqual(self.merged(merge(self.repo, "feature")), self.head)

    def test_a_merge_after_main_moved_is_not_covered(self):
        self.repo.commit({"Klassik/Other.swift": "b"})
        self.assertIsNone(self.merged(merge(self.repo, "feature")))

    def test_an_equal_tree_from_another_history_is_not_covered(self):
        # Main makes the same change on its own, so the trees match, but the PR run never saw that main.
        self.repo.commit({"Klassik/App.swift": "b"})
        sha = merge(self.repo, "feature")
        self.assertEqual(self.repo.git("rev-parse", f"{sha}^{{tree}}"), self.repo.git("rev-parse", "feature^{tree}"))
        self.assertIsNone(self.merged(sha))

    def test_a_merge_that_adds_a_change_is_not_covered(self):
        self.repo.git("merge", "-q", "--no-ff", "--no-commit", "feature")
        sha = self.repo.commit({"Klassik/Other.swift": "c"})
        self.assertIsNone(self.merged(sha))

    def test_a_plain_commit_and_an_unknown_commit_are_not_covered(self):
        self.assertIsNone(self.merged(self.repo.commit({"Klassik/App.swift": "c"})))
        self.assertIsNone(self.merged("0" * 40))

    def test_covering_accepts_the_green_head_of_a_merge(self):
        sha = merge(self.repo, "feature")
        found = green_test_gate.covering(
            green_test_gate.commits_from(sha, cwd=self.repo.tmp),
            lambda commit: green_test_gate.changed(commit, cwd=self.repo.tmp),
            lambda commit: commit == self.head,
            no_version_diff,
            self.merged,
        )
        self.assertEqual(found, (self.head, None))

    def test_covering_refuses_a_merge_whose_head_is_not_green(self):
        sha = merge(self.repo, "feature")
        found, reason = green_test_gate.covering(
            green_test_gate.commits_from(sha, cwd=self.repo.tmp),
            lambda commit: green_test_gate.changed(commit, cwd=self.repo.tmp),
            lambda commit: False,
            no_version_diff,
            self.merged,
        )
        self.assertIsNone(found)
        self.assertIn(f"no green Test run for {sha}", reason)


def jobs(build="success", test="success"):
    named = {"build": build, "test": test}
    return [{"name": name, "conclusion": conclusion} for name, conclusion in named.items() if conclusion]


class ProvesTests(unittest.TestCase):
    def test_a_run_that_built_and_passed(self):
        self.assertTrue(green_test_gate.proves({"conclusion": "success"}, jobs()))

    def test_refusals(self):
        for run, run_jobs in (
            ({"conclusion": "failure"}, jobs()),
            ({"conclusion": "success"}, jobs(build="skipped")),
            ({"conclusion": "success"}, jobs(build=None)),
            ({"conclusion": "success"}, jobs(test="failure")),
            ({"conclusion": "success"}, jobs(test=None)),
            ({"conclusion": "success"}, []),
        ):
            with self.subTest(run=run, jobs=run_jobs):
                self.assertFalse(green_test_gate.proves(run, run_jobs))

    def test_unreadable_fields_raise(self):
        with self.assertRaises(KeyError):
            green_test_gate.proves({}, jobs())
        with self.assertRaises(KeyError):
            green_test_gate.proves({"conclusion": "success"}, [{"name": "build"}])


class MainTests(unittest.TestCase):
    """main() against a scratch history and a fake API. Every unreadable answer must exit 1."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = History(self.tmp.name)
        self.repo.commit({"Klassik/App.swift": "a"})
        self.repo.git("checkout", "-q", "-b", "feature")
        self.head = self.repo.commit({"Klassik/App.swift": "b"})
        self.repo.git("checkout", "-q", "main")
        self.merge = merge(self.repo, "feature")
        cwd = os.getcwd()
        os.chdir(self.repo.tmp)
        self.addCleanup(os.chdir, cwd)
        self.addCleanup(self.tmp.cleanup)
        patch = mock.patch.dict(os.environ, {"GITHUB_REPOSITORY": "o/r"})
        patch.start()
        self.addCleanup(patch.stop)

    def api(self, builds):
        """A fake API: `builds` maps a commit to the conclusion of the build job of its one successful run."""

        def read(query):
            if "/jobs" in query:
                return {"jobs": jobs(build=builds[query.split("/runs/")[1].split("/")[0]])}
            commit = query.split("head_sha=")[1].split("&")[0]
            runs = [{"id": commit, "conclusion": "success"}] if commit in builds else []
            return {"workflow_runs": runs}

        return read

    def main(self, args, read):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            try:
                green_test_gate.main(args, read)
                code = 0
            except SystemExit as exit:
                code = exit.code
        return code, out.getvalue().strip()

    def test_a_covered_merge_takes_the_green_head(self):
        read = self.api({self.merge: "skipped", self.head: "success"})
        self.assertEqual(self.main([self.merge], read), (0, self.head))
        self.assertEqual(self.main(["merged", self.merge], read), (0, self.head))

    def test_a_merge_with_its_own_green_build_takes_itself(self):
        read = self.api({self.merge: "success"})
        self.assertEqual(self.main([self.merge], read), (0, self.merge))
        self.assertEqual(self.main(["merged", self.merge], read), (1, f"{self.merge} is no merge of a green PR head"))

    def test_a_missing_run_blocks(self):
        for builds in ({}, {self.merge: "skipped"}, {self.merge: "skipped", self.head: "skipped"}):
            with self.subTest(builds=builds):
                for args in ([self.merge], ["merged", self.merge]):
                    self.assertEqual(self.main(args, self.api(builds))[0], 1)

    def test_an_unreadable_answer_blocks(self):
        def fails(query):
            raise subprocess.CalledProcessError(1, ["gh", "api", query])

        def not_json(query):
            return json.loads("<html>")

        for read in (fails, not_json, lambda query: {}, lambda query: {"workflow_runs": [{"id": 1}]}, lambda q: []):
            for args in ([self.merge], ["merged", self.merge]):
                with self.subTest(read=read, args=args):
                    code, out = self.main(args, read)
                    self.assertEqual(code, 1)
                    self.assertTrue(out.startswith("cannot read the history or the Test runs"), out)

    def test_an_unknown_commit_blocks(self):
        read = self.api({})
        self.assertEqual(self.main(["0" * 40], read)[0], 1)
        self.assertEqual(self.main(["merged", "0" * 40], read)[0], 1)


if __name__ == "__main__":
    unittest.main()
