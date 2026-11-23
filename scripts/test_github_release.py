import subprocess
import sys
import unittest
from unittest import mock

import github_release as gr


class Parsing(unittest.TestCase):
    def test_previous_tag_is_the_newest_lower_version(self):
        tags = ["v0.9.0", "v0.10.0", "v0.10.1", "v0.11.0", "other"]
        self.assertEqual(gr.previous_tag(tags, "v0.11.0"), "v0.10.1")
        self.assertEqual(gr.previous_tag(tags, "v0.9.0"), None)
        with self.assertRaises(ValueError):
            gr.previous_tag(tags, "0.11.0")

    def test_pr_number_from_merge_and_squash_subjects(self):
        self.assertEqual(gr.pr_number("Merge pull request #177 from whnr/claude-x"), 177)
        self.assertEqual(gr.pr_number("Retire 52 ADRs (#156)"), 156)
        self.assertIsNone(gr.pr_number("Direct commit"))

    def test_group_by_label_then_first_word(self):
        self.assertEqual(gr.group_of("Add a menu", []), "Added")
        self.assertEqual(gr.group_of("Fix the flash", []), "Fixed")
        self.assertEqual(gr.group_of("Remove steppers", []), "Removed")
        self.assertEqual(gr.group_of("Show rows", []), "Changed")
        self.assertEqual(gr.group_of("Add a menu", ["Fixed"]), "Fixed")
        self.assertEqual(gr.group_of("Add a menu", ["ios"]), "Added")


class Body(unittest.TestCase):
    def test_changes_group_in_fixed_order_and_skip_empty_groups(self):
        text = gr.render_changes(
            [("Fixed", "Fix A", "[#1](u1)"), ("Added", "Add B", "[#2](u2)"), ("Fixed", "Fix C", "[#3](u3)")]
        )
        self.assertEqual(
            text,
            "## Changes\n\n### Added\n- Add B: [#2](u2)\n\n### Fixed\n- Fix A: [#1](u1)\n- Fix C: [#3](u3)",
        )

    def test_no_change_fails(self):
        with self.assertRaises(ValueError):
            gr.render_changes([])

    def test_body_is_summary_then_changes(self):
        body = gr.build_body("## Summary\n\n- One.\n", "## Changes\n\n### Added\n- X: [#1](u)")
        self.assertTrue(body.startswith("## Summary\n\n- One.\n\n## Changes"))

    def test_empty_summary_fails(self):
        for summary in ("", "## Summary\n\n", "- One."):
            with self.subTest(summary=summary), self.assertRaises(ValueError):
                gr.build_body(summary, "## Changes")


class Collect(unittest.TestCase):
    def fake_run(self, log):
        def run(*command):
            if command[:2] == ("git", "tag"):
                return "v0.1.0\nv0.2.0\n"
            self.assertEqual(command[:3], ("git", "log", "--first-parent"))
            self.assertEqual(command[-1], "v0.1.0..v0.2.0")
            return log

        return run

    def test_collect_lists_prs_oldest_first_and_skips_the_release_pr(self):
        log = "aaa1111\tMerge pull request #7 from whnr/b\nbbb2222\tFix crash (#6)\nccc3333\tMerge pull request #8 from whnr/r\n"
        prs = {
            "7": {"title": "[sz-1.2] Add menu", "labels": []},
            "6": {"title": "Fix crash", "labels": [{"name": "ios"}]},
            "8": {"title": "Release Klassik 0.2.0", "labels": []},
        }
        with (
            mock.patch.object(gr, "run", self.fake_run(log)),
            mock.patch.object(gr, "gh_json", lambda *a: prs[a[2]]),
        ):
            text = gr.collect("v0.2.0", "o/r")
        self.assertIn("### Added\n- Add menu: [#7](https://github.com/o/r/pull/7)", text)
        self.assertIn("### Fixed\n- Fix crash: [#6](https://github.com/o/r/pull/6)", text)
        self.assertNotIn("Release Klassik", text)

    def test_commit_without_pr_links_the_commit(self):
        with mock.patch.object(gr, "run", self.fake_run("abcdef1234\tDirect fix\n")):
            text = gr.collect("v0.2.0", "o/r")
        self.assertIn("- Direct fix: [abcdef1](https://github.com/o/r/commit/abcdef1234)", text)

    def test_missing_tag_fails(self):
        with mock.patch.object(gr, "run", lambda *c: "v0.1.0\n"), self.assertRaises(ValueError):
            gr.collect("v0.2.0", "o/r")


class Create(unittest.TestCase):
    def result(self, code, err=""):
        return subprocess.CompletedProcess([], code, "", err)

    def test_existing_release_is_left_alone(self):
        with (
            mock.patch.object(subprocess, "run", return_value=self.result(0)),
            mock.patch.object(gr, "run") as run,
        ):
            gr.create("v0.2.0", "o/r")
        run.assert_not_called()

    def test_missing_release_is_created_with_the_body(self):
        with (
            mock.patch.object(subprocess, "run", return_value=self.result(1, "release not found")),
            mock.patch.object(gr, "body_for", return_value="BODY"),
            mock.patch.object(gr, "run") as run,
        ):
            gr.create("v0.2.0", "o/r")
        command = run.call_args.args
        self.assertEqual(command[:4], ("gh", "release", "create", "v0.2.0"))
        self.assertIn("--verify-tag", command)
        self.assertEqual(command[command.index("--notes") + 1], "BODY")

    def test_unknown_lookup_error_fails(self):
        with mock.patch.object(subprocess, "run", return_value=self.result(1, "HTTP 502")), self.assertRaises(RuntimeError):
            gr.create("v0.2.0", "o/r")

    def test_create_failure_exits_non_zero_with_an_error_annotation(self):
        with (
            mock.patch.object(subprocess, "run", return_value=self.result(1, "release not found")),
            mock.patch.object(gr, "body_for", return_value="BODY"),
            mock.patch.object(gr, "run", side_effect=RuntimeError("gh release failed: HTTP 403")),
        ):
            with self.assertRaises(SystemExit) as raised:
                gr.main(["v0.2.0"])
        self.assertTrue(str(raised.exception).startswith("::error::GitHub release failed:"))


if __name__ == "__main__":
    unittest.main()
