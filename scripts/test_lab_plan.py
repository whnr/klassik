"""Tests for the Lab plan and gate: python3 -m unittest discover -s scripts -p "test_lab_plan.py"."""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import lab_plan  # noqa: E402

BUMP = (
    "diff --git a/project.yml b/project.yml\nindex 1..2 100644\n--- a/project.yml\n+++ b/project.yml\n"
    '@@ -9 +9 @@\n-    MARKETING_VERSION: "0.22.0"\n+    MARKETING_VERSION: "0.23.0"\n'
)
EDIT = BUMP.replace("MARKETING_VERSION", "SWIFT_VERSION")


class NeedsLabTests(unittest.TestCase):
    def test_a_version_bump_needs_no_lab_build(self):
        self.assertFalse(lab_plan.needs_lab(["project.yml", "docs/what-to-test.md"], BUMP))

    def test_another_project_change_needs_the_build(self):
        self.assertTrue(lab_plan.needs_lab(["project.yml"], EDIT))

    def test_a_missing_patch_needs_the_build(self):
        self.assertTrue(lab_plan.needs_lab(["project.yml"], ""))

    def test_lab_and_engine_paths_need_the_build(self):
        for path in (
            "KlassikLab/LabModel.swift",
            "KlassikLabTests/X.swift",
            "KlassikEngine/GaplessEngine.swift",
            ".github/workflows/lab.yml",
        ):
            self.assertTrue(lab_plan.needs_lab([path, "project.yml"], BUMP), path)

    def test_app_paths_need_no_lab_build(self):
        self.assertFalse(lab_plan.needs_lab(["Klassik/App.swift", "KlassikTests/X.swift"], ""))


class CoveringTests(unittest.TestCase):
    def find(self, commits, green, changed):
        return lab_plan.covering(commits, lambda sha: sha in green, lambda sha: changed[sha], lambda sha: BUMP)

    def test_own_green_run_covers(self):
        self.assertEqual(self.find(["c", "b"], {"c"}, {"c": ["KlassikLab/A.swift"]}), ("c", None))

    def test_a_version_bump_is_covered_by_the_parent_run(self):
        self.assertEqual(self.find(["c", "b"], {"b"}, {"c": ["project.yml"], "b": ["KlassikLab/A.swift"]}), ("b", None))

    def test_a_lab_change_without_a_run_fails(self):
        found, reason = self.find(["c", "b"], {"b"}, {"c": ["KlassikLab/A.swift"]})
        self.assertIsNone(found)
        self.assertIn("no green Lab run for c", reason)

    def test_no_run_in_the_history_fails(self):
        self.assertIsNone(self.find(["c", "b"], set(), {"c": ["project.yml"], "b": ["Klassik/A.swift"]})[0])


class ProvesTests(unittest.TestCase):
    def test_a_skipped_lab_job_proves_nothing(self):
        run = {"conclusion": "success"}
        self.assertFalse(lab_plan.gate.proves(run, [{"name": "lab", "conclusion": "skipped"}], lab_plan.REQUIRED_JOBS))
        self.assertTrue(lab_plan.gate.proves(run, [{"name": "lab", "conclusion": "success"}], lab_plan.REQUIRED_JOBS))


class PlanTests(unittest.TestCase):
    def test_a_missing_base_builds(self):
        self.assertEqual(lab_plan.plan("", "abc"), "true")
        self.assertEqual(lab_plan.plan("0" * 40, "abc"), "true")

    def test_an_unreadable_range_builds(self):
        self.assertEqual(lab_plan.plan("nonexistent1", "nonexistent2", cwd="/"), "true")


if __name__ == "__main__":
    unittest.main()
