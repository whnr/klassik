"""Tests for the screenshot scripts: python3 -m unittest discover -s scripts -p "test_screens.py"."""

import contextlib
import io
import os
import pathlib
import re
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
    func launch() {
        if connect { snap(app, "01-connect") }
    }
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
        self.assertEqual(screen_report.expected(WALK, "all"), ["01-connect", "02-home", "09-filter", "10-albums"])
        self.assertEqual(screen_report.expected(WALK, "true"), ["01-connect", "02-home", "09-filter", "10-albums"])

    def test_named_areas(self):
        self.assertEqual(screen_report.expected(WALK, "settings"), ["09-filter", "10-albums"])
        self.assertEqual(screen_report.expected(WALK, "browse, settings"), ["02-home", "09-filter", "10-albums"])

    def test_the_real_walk_has_every_area(self):
        source = screen_report.WALK.read_text()
        self.assertTrue(screen_report.expected(source, "all"))
        for area in ("browse", "playback", "settings"):
            self.assertTrue(screen_report.expected(source, area), area)


class RetryReportTests(unittest.TestCase):
    def test_scripts_report_retries_and_preserve_test_exit_status(self):
        root = screen_report.ROOT
        for script in ("screens.sh", "release-launch.sh"):
            for status in (0, 65):
                with self.subTest(script=script, status=status), tempfile.TemporaryDirectory() as directory:
                    temporary = pathlib.Path(directory)
                    for name in ("xcodegen", "xcrun"):
                        path = temporary / name
                        path.write_text('#!/bin/bash\necho "${2:-$1}" >> "$TEST_COMMANDS"\nexit 0\n')
                        path.chmod(0o755)
                    xcodebuild = temporary / "xcodebuild"
                    xcodebuild.write_text(
                        "#!/bin/bash\n"
                        'echo "$1" >> "$TEST_COMMANDS"\n'
                        '[ "$1" != build-for-testing ] || exit 0\n'
                        "echo \"Test Case '-[Tests testPlay]' failed (1.0 seconds).\"\n"
                        'if [ "$TEST_STATUS" = 0 ]; then state=passed; else state=failed; fi\n'
                        "echo \"Test Case '-[Tests testPlay]' $state (1.0 seconds).\"\n"
                        'exit "$TEST_STATUS"\n'
                    )
                    xcodebuild.chmod(0o755)
                    env = {
                        **os.environ,
                        "PATH": f"{temporary}:{os.environ['PATH']}",
                        "KLASSIK_PHASE": "all",
                        "KLASSIK_UI": "false",
                        "KLASSIK_SIMULATOR_UDID": "fixture",
                        "TEST_STATUS": str(status),
                        "TEST_COMMANDS": str(temporary / "commands"),
                        "GITHUB_STEP_SUMMARY": str(temporary / "summary"),
                    }
                    out = temporary / "out"
                    run = subprocess.run(
                        ["bash", str(root / "scripts" / script), str(out)],
                        env=env,
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(run.returncode, status, run.stdout + run.stderr)
                    reports = list(out.glob("*-retries.txt"))
                    self.assertEqual(len(reports), 1)
                    outcome = "recovered" if status == 0 else "failed"
                    self.assertIn(f"| 2 | {outcome} |", reports[0].read_text())
                    self.assertTrue(list(out.glob("*.log")))
                    commands = (temporary / "commands").read_text().splitlines()
                    self.assertLess(commands.index("bootstatus"), commands.index("build-for-testing"))

    def test_clean_run_has_no_failed_attempts(self):
        text = screen_report.retry_report("Test Case '-[Tests testPlay]' passed (1.0 seconds).")
        self.assertIn("No failed test attempts", text)
        self.assertNotIn("recovered", text)

    def test_recovered_xctest_keeps_first_failure_and_attempt_count(self):
        text = screen_report.retry_report(
            "Test Case '-[Tests testPlay]' started.\n"
            "Tests.swift:9: error: -[Tests testPlay] : XCTAssertTrue failed\n"
            "Test Case '-[Tests testPlay]' failed (1.0 seconds).\n"
            "Test Case '-[Tests testPlay]' started.\n"
            "Test Case '-[Tests testPlay]' passed (1.0 seconds).\n"
        )
        self.assertIn("-[Tests testPlay] | 2 | recovered | line 3:", text)
        self.assertIn("XCTAssertTrue failed", text)

    def test_exhausted_xctest_reports_failure(self):
        text = screen_report.retry_report("Test Case '-[Tests testPlay]' failed (1.0 seconds).\n" * 2)
        self.assertIn("-[Tests testPlay] | 2 | failed | line 1:", text)

    def test_interleaved_swift_tests_keep_their_issues(self):
        text = screen_report.retry_report(
            "✘ Test play() recorded an issue at Tests.swift:9: Expectation failed: ready\n"
            "✔ Test stop() passed after 0.001 seconds.\n"
            "✘ Test play() failed after 0.002 seconds with 1 issue.\n"
            "✔ Test play() passed after 0.001 seconds.\n"
        )
        self.assertIn("play() | 2 | recovered | line 3:", text)
        self.assertIn("Expectation failed: ready", text)
        self.assertNotIn("stop()", text)

    def test_swift_parameterized_failure_is_one_attempt(self):
        text = screen_report.retry_report(
            "✘ Test play(mode:) recorded an issue at Tests.swift:9: Expectation failed\n"
            "✘ Test play(mode:) with 3 test cases failed after 0.002 seconds with 1 issue.\n"
            "✘ Test play(mode:) recorded an issue at Tests.swift:9: Expectation failed again\n"
            "✘ Test play(mode:) with 3 test cases failed after 0.002 seconds with 1 issue.\n"
        )
        self.assertIn("play(mode:) | 2 | failed", text)
        self.assertNotIn("failed again", text)

    def test_unretried_failure_and_markdown_escaping(self):
        text = screen_report.retry_report(
            "Test Case '-[Tests testPlay]' started.\n"
            "Tests.swift:9: error: Expected a | b\n"
            "Test Case '-[Tests testPlay]' failed (1.0 seconds).\n"
        )
        self.assertIn("| 1 | failed |", text)
        self.assertIn("a \\| b", text)


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
            path = reports / "walk-playback-queue" / "results.txt"
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
        every = [
            ("places-browse", "01-connect"),
            ("places-browse", "02-home"),
            ("settings-timeline", "09-filter"),
            ("settings-timeline", "10-albums"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            reports = self.walk_reports(directory, every)
            self.assertEqual(screen_report.aggregate_ui(reports, "all", WALK), "passed")
            self.assertEqual(screen_report.unexplained_gaps(reports, "all", WALK), {})
        with tempfile.TemporaryDirectory() as directory:
            reports = self.walk_reports(directory, every[:3])
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

    def test_the_connect_snap_belongs_to_places(self):
        self.assertEqual(screen_report.expected(WALK, "all"), ["01-connect", "02-home", "09-filter", "10-albums"])
        self.assertEqual(screen_report.expected(WALK, "places"), ["01-connect"])
        self.assertNotIn("01-connect", screen_report.expected(WALK, "settings"))

    def test_a_passed_walk_must_keep_the_connect_screenshot(self):
        shots = [("places-browse", "02-home"), ("settings-timeline", "09-filter"), ("settings-timeline", "10-albums")]
        with tempfile.TemporaryDirectory() as directory:
            reports = self.walk_reports(directory, shots)
            self.assertEqual(screen_report.unexplained_gaps(reports, "all", WALK), {"places-browse": ["01-connect"]})
            self.assertEqual(screen_report.aggregate_ui(reports, "all", WALK), "incomplete")
            self.assertEqual(screen_report.aggregate_ui(reports, "settings", WALK), "passed")

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
        self.assertEqual(self.groups("pull_request", messages="Fix parsing\n\nui: is not a request"), ("false", []))

    def test_pull_request_walks_the_union_of_its_requests(self):
        messages = "First\n\n[ui: browse]\n\nSecond\n\n[UI: Playback, browse]\n"
        self.assertEqual(
            self.groups("pull_request", messages=messages),
            ("playback,browse", ["playback-queue", "playback-controls", "places-browse"]),
        )

    def test_pull_request_can_request_everything(self):
        ui, groups = self.groups("pull_request", messages="[ui: browse]\n[ui: all]")
        self.assertEqual((ui, len(groups)), ("all", 4))

    def test_pull_request_warns_and_keeps_valid_requests(self):
        for messages, expected in (
            ("[ui: brwse]", ("false", [])),
            ("[ui: places,library]\n[ui: performers]", ("places", ["places-browse"])),
            ("[ui: all]\n[ui: brwse]", ("all", list(screen_report.UI_GROUPS))),
        ):
            with self.subTest(messages=messages), contextlib.redirect_stderr(io.StringIO()) as warnings:
                self.assertEqual(self.groups("pull_request", messages=messages), expected)
                self.assertIn("::warning::Ignoring unknown UI areas:", warnings.getvalue())
                for group in screen_report.UI_GROUPS:
                    self.assertIn(group, warnings.getvalue())
                self.assertIn("Valid UI areas: playback, places, browse, settings, timeline", warnings.getvalue())

    def test_main_push_runs_no_walk(self):
        self.assertEqual(self.groups("push"), ("false", []))

    def test_nightly_and_ci_push_walk_everything(self):
        for event, ref in (("schedule", "refs/heads/main"), ("push", "refs/heads/ci")):
            ui, matrix = screen_report.plan(event, "", "", ref=ref)
            self.assertEqual(ui, "all")
            self.assertEqual(len(matrix["include"]), 4)

    def test_release_title_walks_everything(self):
        for title in ("Release Klassik 0.15.0", "[sz-123] Release Klassik 0.15.0"):
            ui, matrix = screen_report.plan("pull_request", "", "", title)
            self.assertEqual(ui, "all")
            self.assertEqual(len(matrix["include"]), 4)

    def test_unclear_release_versions_walk_everything(self):
        for title in ("Release Klassik 1.0", "Release Klassik 0.16.x", "Release Klassik ", "Release Klassik 0.16.00"):
            with self.subTest(title=title):
                self.assertEqual(screen_report.plan("pull_request", "", "[ui: browse]", title)[0], "all")

    def test_patch_release_walks_only_requested_areas(self):
        for title in ("Release Klassik 0.16.1", "[sz-123] Release Klassik 0.16.10"):
            with self.subTest(title=title):
                ui, matrix = screen_report.plan("pull_request", "", "Fix\n\n[ui: browse]\n", title)
                self.assertEqual((ui, [entry["group"] for entry in matrix["include"]]), ("browse", ["places-browse"]))
        self.assertEqual(screen_report.plan("pull_request", "", "", "Release Klassik 0.16.1")[0], "false")

    def test_other_titles_are_not_releases(self):
        self.assertEqual(screen_report.plan("pull_request", "", "", "Fix the Release Klassik 0.16.0 notes")[0], "false")

    def test_playback_shards_cover_every_method_and_screenshot_once(self):
        source = screen_report.WALK.read_text()
        queue = screen_report.group_tests("playback-queue")
        controls = screen_report.group_tests("playback-controls")
        self.assertFalse(set(queue) & set(controls))
        playback = source.split("class PlaybackScreens:", 1)[1].split("class TimelineScreens:", 1)[0]
        self.assertEqual(set(queue + controls), set(re.findall(r"func (test\w+)\(", playback)))
        queue_shots = set(screen_report.expected(source, "playback", queue))
        control_shots = set(screen_report.expected(source, "playback", controls))
        self.assertFalse(queue_shots & control_shots)
        self.assertEqual(queue_shots | control_shots, set(screen_report.expected(source, "playback")))
        self.assertTrue(queue_shots)
        self.assertTrue(control_shots)

    def test_each_playback_shard_requires_only_its_own_screenshots(self):
        source = screen_report.WALK.read_text()
        with tempfile.TemporaryDirectory() as directory:
            reports = pathlib.Path(directory)
            for group in ("playback-queue", "playback-controls"):
                report = reports / f"walk-{group}"
                report.mkdir()
                (report / "results.txt").write_text("build=passed\nui=passed\n")
                for name in screen_report.expected(source, "playback", screen_report.group_tests(group)):
                    (report / f"{name}.png").touch()
            self.assertEqual(screen_report.aggregate_ui(reports, "playback", source), "passed")
            missing = next((reports / "walk-playback-queue").glob("*.png"))
            missing.unlink()
            self.assertEqual(
                screen_report.unexplained_gaps(reports, "playback", source), {"playback-queue": [missing.stem]}
            )

    def test_run_by_hand_takes_the_input(self):
        self.assertEqual(
            self.groups("workflow_dispatch"),
            ("all", ["playback-queue", "playback-controls", "places-browse", "settings-timeline"]),
        )
        self.assertEqual(self.groups("workflow_dispatch", "Settings"), ("settings", ["settings-timeline"]))
        self.assertEqual(self.groups("workflow_dispatch", "false"), ("false", []))
        with self.assertRaises(ValueError):
            screen_report.plan("workflow_dispatch", "brwse", "")


class ConsoleReportTests(unittest.TestCase):
    def test_counts_signs_and_skips_missing_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "unit-console.txt"
            path.write_text("ok\nFatal error: x\nThread 1 crashed\nSwift runtime: bad\nfine\n")
            text = screen_report.console_report([path, pathlib.Path(tmp) / "none-console.txt"])
        self.assertIn("`unit-console.txt`: 3 lines", text)
        self.assertNotIn("none-console", text)

    def test_no_file(self):
        self.assertIn("No console file", screen_report.console_report([]))


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

    def test_branch_name_is_url_encoded(self):
        query = screen_baseline.runs_query("o/r", "fix&x=1#a b", "completed")
        self.assertIn("branch=fix%26x%3D1%23a%20b&status=completed", query)

    def test_usable_needs_screenshots(self):
        screens = {"name": "screens", "expired": False, "size_in_bytes": 2_000_000}
        self.assertTrue(screen_baseline.usable([screens]))
        self.assertFalse(screen_baseline.usable([{**screens, "size_in_bytes": 1_300}]))
        self.assertFalse(screen_baseline.usable([{**screens, "expired": True}]))
        self.assertFalse(screen_baseline.usable([{**screens, "name": "screens-diff"}]))
        self.assertFalse(screen_baseline.usable([]))


if __name__ == "__main__":
    unittest.main()
