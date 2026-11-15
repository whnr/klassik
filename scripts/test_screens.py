"""Tests for the screenshot scripts: python3 -m unittest discover -s scripts -p "test_screens.py"."""

import pathlib
import subprocess
import sys
import tempfile
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


class MatrixTests(unittest.TestCase):
    def test_area_names_ignore_case_and_spaces(self):
        self.assertEqual(screen_report.selected_areas("Browse, Settings", "places,browse"), "browse")
        self.assertEqual(screen_report.selected_areas("Browse, Settings", "settings,timeline"), "settings")
        self.assertEqual(screen_report.selected_areas("Browse, Settings", "playback"), "false")

    def test_unknown_area_is_rejected_even_with_known_area(self):
        for request in ("unknown", "browse,unknown", "browse,"):
            with self.subTest(request=request), self.assertRaises(ValueError):
                screen_report.selected_areas(request, "playback")

    def test_all_and_disabled(self):
        for request in ("", "all", "true"):
            self.assertEqual(screen_report.selected_areas(request, "places,browse"), "places,browse")
        self.assertEqual(screen_report.selected_areas("false", "places,browse"), "false")

    def test_aggregation_requires_completed_selected_groups(self):
        with tempfile.TemporaryDirectory() as directory:
            reports = pathlib.Path(directory)
            for group in screen_report.UI_GROUPS:
                path = reports / f"walk-{group}"
                path.mkdir()
                (path / "results.txt").write_text("build=passed\nui=not run\nui=passed\n")
            self.assertEqual(screen_report.aggregate_ui(reports, "all", ""), "passed")
            path = reports / "walk-playback" / "results.txt"
            path.unlink()
            self.assertEqual(screen_report.aggregate_ui(reports, "all", ""), "incomplete")
            self.assertEqual(screen_report.aggregate_ui(reports, "Browse,Settings", ""), "passed")
            for text in ("", "build=passed\n", "build=passed\nui=not run\n", "build=failed\nui=passed\n"):
                path.write_text(text)
                self.assertEqual(screen_report.aggregate_ui(reports, "all", ""), "incomplete")
            path.write_text("build=passed\nui=not run\nui=failed\n")
            self.assertEqual(screen_report.aggregate_ui(reports, "all", ""), "failed")
            self.assertEqual(screen_report.aggregate_ui(reports, "false", ""), "not run")

    def walk_reports(self, directory, shots, browse="passed"):
        reports = pathlib.Path(directory)
        for group in screen_report.UI_GROUPS:
            path = reports / f"walk-{group}"
            path.mkdir()
            state = browse if group == "places-browse" else "passed"
            (path / "results.txt").write_text(f"build=passed\nui={state}\n")
        for group, name in shots:
            (reports / f"walk-{group}" / f"{name}.png").write_bytes(b"")
        return reports

    def test_a_passed_walk_must_keep_every_screenshot(self):
        every = [("places-browse", "02-home"), ("settings-timeline", "09-filter"), ("settings-timeline", "10-albums")]
        with tempfile.TemporaryDirectory() as directory:
            reports = self.walk_reports(directory, every)
            self.assertEqual(screen_report.aggregate_ui(reports, "all", WALK), "passed")
            self.assertEqual(screen_report.unexplained_gaps(reports, "all", WALK), {})
        with tempfile.TemporaryDirectory() as directory:
            reports = self.walk_reports(directory, every[:2])
            self.assertEqual(screen_report.aggregate_ui(reports, "all", WALK), "incomplete")
            self.assertEqual(screen_report.unexplained_gaps(reports, "all", WALK), {"settings-timeline": ["10-albums"]})
            # A walk that skips the settings area expects none of its screenshots.
            self.assertEqual(screen_report.aggregate_ui(reports, "browse", WALK), "passed")

    def test_a_failed_walk_explains_its_own_gaps(self):
        with tempfile.TemporaryDirectory() as directory:
            reports = self.walk_reports(
                directory, [("settings-timeline", "09-filter"), ("settings-timeline", "10-albums")], browse="failed"
            )
            self.assertEqual(screen_report.unexplained_gaps(reports, "all", WALK), {})
            self.assertEqual(screen_report.aggregate_ui(reports, "all", WALK), "failed")

    def test_the_command_names_the_gaps(self):
        with tempfile.TemporaryDirectory() as directory:
            self.walk_reports(directory, [])
            result = subprocess.run(
                [sys.executable, str(pathlib.Path(screen_report.__file__)), "aggregate-ui", directory, "all"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "ui=incomplete\n")
            self.assertIn("walk-settings-timeline passed without screenshots: ", result.stderr)
            self.assertIn("15g-timeline-setting", result.stderr)

    def test_incomplete_aggregation_command_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, str(pathlib.Path(screen_report.__file__)), "aggregate-ui", directory, "all"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "ui=incomplete\n")

    def test_incomplete_results_block_without_required_policy(self):
        text = screen_report.ui_result({"ui": "incomplete", "ui_required": "false"})
        self.assertIn("**FAILED**", text)
        self.assertNotIn("tolerated", text)


class PlanTests(unittest.TestCase):
    def groups(self, event, dispatch_input="", messages=""):
        ui, matrix = screen_report.plan(event, dispatch_input, messages)
        return ui, [entry["group"] for entry in matrix["include"]]

    def test_pull_request_without_request_runs_only_unit_tests(self):
        self.assertEqual(
            self.groups("pull_request", messages="Fix parsing\n\nui: is not a request"), ("false", ["unit"])
        )

    def test_pull_request_walks_the_union_of_its_requests(self):
        messages = "First\n\n[ui: browse]\n\nSecond\n\n[UI: Playback, browse]\n"
        self.assertEqual(
            self.groups("pull_request", messages=messages), ("playback,browse", ["unit", "playback", "places-browse"])
        )

    def test_pull_request_can_request_everything(self):
        ui, groups = self.groups("pull_request", messages="[ui: browse]\n[ui: all]")
        self.assertEqual((ui, len(groups)), ("all", 4))

    def test_pull_request_rejects_unknown_areas(self):
        with self.assertRaises(ValueError):
            screen_report.plan("pull_request", "", "[ui: brwse]")

    def test_pushes_walk_everything(self):
        self.assertEqual(self.groups("push"), ("all", ["unit", "playback", "places-browse", "settings-timeline"]))

    def test_run_by_hand_takes_the_input(self):
        self.assertEqual(
            self.groups("workflow_dispatch"), ("all", ["unit", "playback", "places-browse", "settings-timeline"])
        )
        self.assertEqual(self.groups("workflow_dispatch", "Settings"), ("settings", ["unit", "settings-timeline"]))
        self.assertEqual(self.groups("workflow_dispatch", "false"), ("false", ["unit"]))
        with self.assertRaises(ValueError):
            screen_report.plan("workflow_dispatch", "brwse", "")


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
