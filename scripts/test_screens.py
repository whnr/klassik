"""Tests for the screenshot scripts: python3 -m unittest discover -s scripts -p "test_screens.py"."""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import screen_baseline  # noqa: E402
import screen_report  # noqa: E402

WALK = """
final class BrowseScreens: ScreensTestCase {
    func testHome() throws {
        snap(app, "02-home")
    }
}
final class SettingsScreens: ScreensTestCase {
    func testFilter() throws {
        snap(app, "09-filter")
        snap(app, "10-albums")
    }
}
class ScreensTestCase: XCTestCase {
    func snap(_ app: XCUIApplication, _ name: String) {}
}
"""


def run(run_id, branch="ci"):
    return {"id": run_id, "head_sha": "abcdef123456", "head_branch": branch}


class ExpectedTests(unittest.TestCase):
    def test_no_walk_expects_nothing(self):
        self.assertEqual(screen_report.expected(WALK, "false"), [])
        self.assertEqual(screen_report.expected(WALK, ""), [])

    def test_all_areas(self):
        self.assertEqual(screen_report.expected(WALK, "all"), ["02-home", "09-filter", "10-albums"])
        self.assertEqual(screen_report.expected(WALK, "true"), ["02-home", "09-filter", "10-albums"])

    def test_named_areas(self):
        self.assertEqual(screen_report.expected(WALK, "settings"), ["09-filter", "10-albums"])
        self.assertEqual(screen_report.expected(WALK, "browse, settings"), ["02-home", "09-filter", "10-albums"])

    def test_the_real_walk_has_every_area(self):
        source = screen_report.WALK.read_text()
        self.assertTrue(screen_report.expected(source, "all"))
        for area in ("browse", "playback", "settings"):
            self.assertTrue(screen_report.expected(source, area), area)


class SummaryTests(unittest.TestCase):
    def results(self, **changes):
        text = "ui_areas=all\nui_required=false\nbuild=failed\nunit=not run\nui=not run\n"
        text += "".join(f"{key}={value}\n" for key, value in changes.items())
        return screen_report.read_results(text)

    def test_last_value_wins(self):
        self.assertEqual(self.results(build="passed")["build"], "passed")
        self.assertEqual(self.results()["build"], "failed")

    def test_tolerated_failure_reads_as_failure(self):
        results = self.results(build="passed", unit="passed", ui="failed")
        text, missing = screen_report.summary(results, ["02-home"], ["02-home", "09-filter"])
        self.assertIn("| UI tests | **FAILED, tolerated**", text)
        self.assertIn("| UI tests required | no |", text)
        self.assertIn("| Screenshots captured | 1 of 2 |", text)
        self.assertIn("| Screenshots missing | 09-filter |", text)
        self.assertEqual(missing, ["09-filter"])

    def test_required_failure_blocks(self):
        results = self.results(build="passed", unit="passed", ui="failed", ui_required="true")
        text, _ = screen_report.summary(results, [], ["02-home"])
        self.assertIn("blocks the run", text)
        self.assertIn("| UI tests required | yes |", text)
        self.assertIn("the comparison does not run", text)

    def test_failed_build_runs_no_test(self):
        text, _ = screen_report.summary(self.results(), [], [])
        self.assertIn("| Build | failed |", text)
        self.assertIn("| Unit tests | not run |", text)
        self.assertIn("| UI tests | not run |", text)

    def test_all_passed(self):
        results = self.results(build="passed", unit="passed", ui="passed")
        text, missing = screen_report.summary(results, ["02-home"], ["02-home"], "https://example.org/run#artifacts")
        self.assertIn("| UI tests | passed |", text)
        self.assertIn("| Screenshots missing | none |", text)
        self.assertIn("https://example.org/run#artifacts", text)
        self.assertEqual(missing, [])


class DiffSummaryTests(unittest.TestCase):
    def test_counts(self):
        report = {
            "a.png": {"band": "new"},
            "b.png": {"band": "large"},
            "c.png": {"band": "small"},
            "d.png": {"band": "same"},
            "e.png": {"band": "same"},
        }
        sources = {"b.png": "run 7, abcdef1, topic", "c.png": "run 7, abcdef1, topic", "d.png": "run 3, 1234567, ci"}
        text = screen_report.diff_summary(report, ["f"], sources)
        self.assertIn("| 1 | 2 (1 large) | 2 | 1 |", text)
        self.assertIn("Baseline: run 3, 1234567, ci; run 7, abcdef1, topic.", text)
        self.assertIn("Missing in this run: f.", text)

    def test_no_report_is_skipped_not_passed(self):
        self.assertIn("Skipped", screen_report.diff_summary(None, [], {}))

    def test_no_baseline(self):
        text = screen_report.diff_summary({"a.png": {"band": "new"}}, [], {})
        self.assertIn("none found", text)


class BaselineTests(unittest.TestCase):
    def test_branch_runs_come_before_the_fallback(self):
        order = screen_baseline.candidates([run(9, "topic"), run(7, "topic")], [run(8), run(5)], this_run=10)
        self.assertEqual([r["id"] for r in order], [9, 7, 8, 5])

    def test_a_run_is_never_its_own_baseline(self):
        order = screen_baseline.candidates([run(9, "topic"), run(7, "topic")], [run(9), run(5)], this_run=9)
        self.assertEqual([r["id"] for r in order], [7, 5])

    def test_no_branch_run_falls_back(self):
        order = screen_baseline.candidates([], [run(8), run(5)], this_run=10)
        self.assertEqual([r["id"] for r in order], [8, 5])

    def test_usable_needs_screenshots(self):
        screens = {"name": "screens", "expired": False, "size_in_bytes": 2_000_000}
        self.assertTrue(screen_baseline.usable([screens]))
        self.assertFalse(screen_baseline.usable([{**screens, "size_in_bytes": 1_300}]))
        self.assertFalse(screen_baseline.usable([{**screens, "expired": True}]))
        self.assertFalse(screen_baseline.usable([{**screens, "name": "screens-diff"}]))
        self.assertFalse(screen_baseline.usable([]))


if __name__ == "__main__":
    unittest.main()
