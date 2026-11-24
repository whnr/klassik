"""Tests for the screenshot scripts: python3 -m unittest discover -s scripts -p "test_screens.py"."""

import contextlib
import io
import json
import os
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
    func launch() {
        if connect { snap(app, "01-connect") }
    }
    func snap(_ app: XCUIApplication, _ name: String) {}
}
"""


def case_tree(result, messages, extra=None):
    """`xcresulttool get test-results tests` output with one failed case, and optionally a second."""

    def case(name, outcome, texts):
        return {
            "nodeType": "Test Case",
            "name": f"{name}()",
            "nodeIdentifier": f"PlayTests/{name}()",
            "result": outcome,
            "children": [{"nodeType": "Failure Message", "name": text} for text in texts],
        }

    cases = [case("testPlay", result, messages)]
    if extra:
        cases.append(case(extra[0], "Failed", extra[1]))
    suite = {"nodeType": "Test Suite", "name": "PlayTests", "children": cases}
    bundle = {"nodeType": "Unit test bundle", "name": "KlassikTests", "children": [suite]}
    return {"testNodes": [{"nodeType": "Test Plan", "name": "Klassik", "children": [bundle]}]}


def run(run_id, branch="main"):
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
        for script in ("release-launch.sh",):
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

    def run_screens(
        self,
        tests_json,
        fail_first=True,
        always_fail=False,
        phase="unit",
        extra_env=None,
        retry_json=None,
        expected=("PlayTests/testPlay",),
    ):
        """Runs scripts/screens.sh with a fake xcodebuild whose first run fails (and whose later runs pass unless
        `always_fail`), and a fake xcresulttool that prints `tests_json` for the first bundle and `retry_json`
        (default: the test passes) for the retry bundle. `expected` is what -enumerate-tests lists; None makes it
        fail. Returns (result, out dir, commands)."""
        temporary = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(temporary, ignore_errors=True))
        for name in ("xcodegen", "xcrun"):
            path = temporary / name
            path.write_text(
                "#!/bin/bash\n"
                'if [ "$1" = xcresulttool ] && [ "$3" = test-results ]; then\n'
                '  case "$*" in *-retry.xcresult*) cat "$TEST_JSON_RETRY" ;; *) cat "$TEST_JSON" ;; esac; exit 0; fi\n'
                'if [ "$1" = xcresulttool ] && [ "$2" = export ]; then dest="${@: -1}"; mkdir -p "$dest"; '
                'echo "[]" > "$dest/manifest.json"; exit 0; fi\n'
                'if [ "$1" = xcresulttool ]; then exit 0; fi\n'
                'echo "${2:-$1}" >> "$TEST_COMMANDS"\n'
                "exit 0\n"
            )
            path.chmod(0o755)
        (temporary / "tests.json").write_text(tests_json if isinstance(tests_json, str) else json.dumps(tests_json))
        (temporary / "retry.json").write_text(json.dumps(retry_json or case_tree("Passed", [])))
        enumeration = {"values": [{"enabledTests": [{"identifier": f"{name}()"} for name in expected or []]}]}
        (temporary / "enumeration.json").write_text(json.dumps(enumeration))
        xcodebuild = temporary / "xcodebuild"
        xcodebuild.write_text(
            "#!/bin/bash\n"
            'case "$*" in *-enumerate-tests*)\n'
            '  [ "$ENUMERATE_FAILS" != 1 ] || exit 1\n'
            "  while [ $# -gt 0 ]; do\n"
            '    [ "$1" != -test-enumeration-output-path ] || cp "$ENUMERATION" "$2"; shift\n'
            "  done\n"
            "  exit 0 ;;\nesac\n"
            'echo "$*" >> "$TEST_COMMANDS"\n'
            '[ "$1" != build-for-testing ] || { echo "SwiftDriver Klassik"; exit 0; }\n'
            'while [ $# -gt 0 ]; do [ "$1" != -resultBundlePath ] || mkdir -p "$2"; shift; done\n'
            'n=$(grep -c "^test-without-building" "$TEST_COMMANDS")\n'
            'if [ "$n" = 1 ] || [ "$ALWAYS_FAIL" = 1 ]; then state=failed; code=65; else state=passed; code=0; fi\n'
            "echo \"Test Case '-[Tests testPlay]' $state (1.0 seconds).\"\n"
            'exit "$code"\n'
        )
        xcodebuild.chmod(0o755)
        env = {
            **os.environ,
            "PATH": f"{temporary}:{os.environ['PATH']}",
            "KLASSIK_PHASE": phase,
            "KLASSIK_UI": "false",
            "KLASSIK_SIMULATOR_UDID": "fixture",
            "TEST_COMMANDS": str(temporary / "commands"),
            "TEST_JSON": str(temporary / "tests.json"),
            "TEST_JSON_RETRY": str(temporary / "retry.json"),
            "ENUMERATION": str(temporary / "enumeration.json"),
            "ENUMERATE_FAILS": "0" if expected is not None else "1",
            "ALWAYS_FAIL": "1" if always_fail else "0",
            "GITHUB_STEP_SUMMARY": str(temporary / "summary"),
            **(extra_env or {}),
        }
        (temporary / "commands").write_text("")
        out = temporary / "out"
        run = subprocess.run(
            ["bash", str(screen_report.ROOT / "scripts" / "screens.sh"), str(out)],
            env=env,
            capture_output=True,
            text=True,
        )
        commands = (temporary / "commands").read_text().splitlines()
        return run, out, commands

    def test_assertion_failure_runs_once_and_fails(self):
        tests = case_tree("Failed", ["XCTAssertEqual failed: (1) is not equal to (2)"])
        run, out, commands = self.run_screens(tests)
        self.assertEqual(run.returncode, 65, run.stdout + run.stderr)
        self.assertEqual(sum(c.startswith("test-without-building") for c in commands), 1)
        self.assertNotIn("Flaky", (out / "unit-retries.txt").read_text())

    def test_launch_without_process_id_is_infrastructure(self):
        message = "Application 'de.whnr.klassik' does not have a process ID"
        self.assertTrue(screen_report.infrastructure_failure([message]))
        self.assertFalse(screen_report.infrastructure_failure(["Application 'de.whnr.klassik' crashed"]))

    def test_runner_crash_retries_only_the_failed_test_and_reports_it_flaky(self):
        tests = case_tree("Failed", ["Test runner crashed: lost connection to the test host"])
        run, out, commands = self.run_screens(tests)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        runs = [c for c in commands if c.startswith("test-without-building")]
        self.assertEqual(len(runs), 2)
        self.assertIn("-only-testing:KlassikTests/PlayTests/testPlay", runs[1])
        self.assertNotIn("-only-testing:KlassikTests ", runs[1])
        report = (out / "unit-retries.txt").read_text()
        self.assertIn("recovered", report)
        self.assertIn("**Flaky**", report)
        self.assertIn("::warning::Flaky test", run.stdout)

    def test_crash_of_the_app_under_test_is_not_retried(self):
        tests = case_tree("Failed", ["Crash: Klassik (1234) crashed", "Application com.klassik.app is not running"])
        run, _, commands = self.run_screens(tests)
        self.assertEqual(run.returncode, 65, run.stdout + run.stderr)
        self.assertEqual(sum(c.startswith("test-without-building") for c in commands), 1)
        self.assertIsNone(screen_report.retry_plan(tests))

    def test_runner_crash_that_fails_again_fails_the_run(self):
        tests = case_tree("Failed", ["Test runner crashed: lost connection to the test host"])
        run, _, commands = self.run_screens(tests, always_fail=True)
        self.assertEqual(run.returncode, 65, run.stdout + run.stderr)
        self.assertEqual(sum(c.startswith("test-without-building") for c in commands), 2)

    def test_crash_does_not_hide_an_assertion_failure_of_the_same_run(self):
        tests = case_tree(
            "Failed", ["Test runner crashed: lost connection"], extra=("testOther", ["XCTAssertTrue failed"])
        )
        run, _, _ = self.run_screens(tests)
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)

    def test_unreadable_bundle_is_not_retried(self):
        run, _, commands = self.run_screens({}, phase="unit")
        # No test case at all in a readable bundle: nothing ran, so the selection runs once more.
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual(sum(c.startswith("test-without-building") for c in commands), 2)

    def test_tests_that_never_ran_are_run_in_the_retry(self):
        # The runner exited early: testOther has no result in the first bundle.
        tests = case_tree("Failed", ["Early unexpected exit, operation never finished bootstrapping"])
        both = case_tree("Passed", [])
        both["testNodes"][0]["children"][0]["children"][0]["children"].append(
            {
                "nodeType": "Test Case",
                "name": "testOther()",
                "nodeIdentifier": "PlayTests/testOther()",
                "result": "Passed",
            }
        )
        expected = ("PlayTests/testPlay", "PlayTests/testOther")
        run, _, commands = self.run_screens(tests, retry_json=both, expected=expected)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        retry = [c for c in commands if c.startswith("test-without-building")][1]
        self.assertIn("-only-testing:KlassikTests/PlayTests/testPlay", retry)
        self.assertIn("-only-testing:KlassikTests/PlayTests/testOther", retry)

    def test_a_retry_that_leaves_a_test_without_a_result_fails(self):
        tests = case_tree("Failed", ["Early unexpected exit, operation never finished bootstrapping"])
        expected = ("PlayTests/testPlay", "PlayTests/testOther")
        run, _, _ = self.run_screens(tests, expected=expected)
        self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("PlayTests/testOther", run.stdout)

    def test_no_list_of_requested_tests_means_no_retry_and_a_failure(self):
        tests = case_tree("Failed", ["Early unexpected exit, operation never finished bootstrapping"])
        run, _, commands = self.run_screens(tests, expected=None)
        self.assertEqual(run.returncode, 65, run.stdout + run.stderr)
        self.assertEqual(sum(c.startswith("test-without-building") for c in commands), 1)

    def test_an_error_of_the_assertion_check_fails_the_run(self):
        # The first bundle is unreadable as JSON: the retry plan fails, so the run stays failed.
        run, _, _ = self.run_screens("{ not json")
        self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_report_commands_exit_2_on_an_error_and_0_otherwise(self):
        script = str(screen_report.ROOT / "scripts" / "screen_report.py")
        with tempfile.TemporaryDirectory() as directory:
            bad = pathlib.Path(directory) / "bad.json"
            bad.write_text("{ not json")
            for command in ("assertion-failures", "retry-plan", "expected-tests"):
                run = subprocess.run(["python3", script, command, str(bad)], capture_output=True, text=True)
                self.assertEqual(run.returncode, 2, command)
            good = pathlib.Path(directory) / "good.json"
            good.write_text(json.dumps(case_tree("Failed", ["XCTAssertEqual failed"])))
            run = subprocess.run(["python3", script, "assertion-failures", str(good)], capture_output=True, text=True)
            self.assertEqual((run.returncode, run.stdout.strip()), (0, "KlassikTests/PlayTests/testPlay"))

    def test_unfinished_and_unrun_tests(self):
        failed, passed = case_tree("Failed", ["XCTAssertEqual failed"]), case_tree("Passed", [])
        expected = ["PlayTests/testOther", "PlayTests/testPlay"]
        self.assertEqual(screen_report.unfinished_tests(expected, [failed, passed]), ["PlayTests/testOther"])
        self.assertEqual(
            screen_report.unfinished_tests(["PlayTests/testPlay"], [passed, failed]), ["PlayTests/testPlay"]
        )
        self.assertEqual(
            screen_report.unrun_tests(expected, "KlassikTests", passed), ["KlassikTests/PlayTests/testOther"]
        )
        enumeration = {
            "values": [
                {
                    "enabledTests": [{"identifier": "KlassikTests/PlayTests/testPlay()"}],
                    "disabledTests": [{"identifier": "A/b"}],
                }
            ]
        }
        self.assertEqual(screen_report.enumerated_tests(enumeration), ["PlayTests/testPlay"])

    def test_the_pr_unit_run_skips_the_measurement_suite_and_the_measure_phase_runs_it(self):
        tests = case_tree("Failed", ["XCTAssertEqual failed"])
        _, _, commands = self.run_screens(tests)
        unit = next(c for c in commands if c.startswith("test-without-building"))
        self.assertIn("-skip-testing:KlassikTests/EarlyPlaybackMeasurementTests", unit)
        run, out, commands = self.run_screens(case_tree("Failed", ["XCTAssertEqual failed"]), phase="measure")
        measure = next(c for c in commands if c.startswith("test-without-building"))
        self.assertIn("-only-testing:KlassikTests/EarlyPlaybackMeasurementTests", measure)
        self.assertIn("-only-testing:KlassikTests/EarlyPlaybackTests", measure)
        self.assertIn("measure=failed", (out / "results.txt").read_text())

    def test_full_run_boots_the_simulator_after_the_build(self):
        tests = case_tree("Failed", ["XCTAssertEqual failed"])
        _, out, commands = self.run_screens(tests, phase="all")
        build = next(i for i, c in enumerate(commands) if c.startswith("build-for-testing"))
        self.assertLess(build, commands.index("bootstatus"))
        timings = (out / "timings.txt").read_text()
        self.assertIn("build-first-output", timings)
        self.assertIn("build-first-compile", timings)

    def test_retry_plan_commands(self):
        crash = case_tree("Failed", ["Early unexpected exit, operation never finished bootstrapping"])
        self.assertEqual(screen_report.retry_plan(crash), ["KlassikTests/PlayTests/testPlay"])
        self.assertIsNone(screen_report.retry_plan(case_tree("Failed", ["XCTAssertEqual failed"])))
        self.assertIsNone(screen_report.retry_plan(case_tree("Failed", [])))
        self.assertEqual(screen_report.retry_plan({"testNodes": []}), ["ALL"])
        self.assertEqual(screen_report.assertion_failures(crash), [])

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
            state = browse if "browse" in screen_report.UI_GROUPS[group] else "passed"
            (path / "results.txt").write_text(f"build=passed\nui={state}\n")
        for group, name in shots:
            (reports / f"walk-{group}" / f"{name}.png").write_bytes(b"")
        return reports

    def test_a_passed_walk_must_keep_every_screenshot(self):
        every = [
            ("places-search", "01-connect"),
            ("browse-pages", "02-home"),
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
        shots = [("browse-pages", "02-home"), ("settings-timeline", "09-filter"), ("settings-timeline", "10-albums")]
        with tempfile.TemporaryDirectory() as directory:
            reports = self.walk_reports(directory, shots)
            self.assertEqual(screen_report.unexplained_gaps(reports, "all", WALK), {"places-search": ["01-connect"]})
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

    def test_head_commit_walks_the_union_of_its_request_lines(self):
        messages = "Fix the player\n\n[ui: browse]\n[UI: Playback, browse]\n"
        self.assertEqual(
            self.groups("pull_request", messages=messages),
            (
                "playback,browse",
                ["playback-queue", "playback-overlay", "playback-controls", "places-search", "browse-pages"],
            ),
        )

    def test_pull_request_can_request_everything(self):
        ui, groups = self.groups("pull_request", messages="[ui: browse]\n[ui: all]")
        self.assertEqual((ui, groups), ("all", list(screen_report.UI_GROUPS)))

    def test_pull_request_warns_and_keeps_valid_requests(self):
        for messages, expected in (
            ("[ui: brwse]", ("false", [])),
            ("[ui: places,library]\n[ui: performers]", ("places", ["places-search"])),
            ("[ui: all]\n[ui: brwse]", ("all", list(screen_report.UI_GROUPS))),
        ):
            with self.subTest(messages=messages), contextlib.redirect_stderr(io.StringIO()) as warnings:
                self.assertEqual(self.groups("pull_request", messages=messages), expected)
                self.assertIn("::warning::Ignoring unknown UI areas:", warnings.getvalue())
                for group in screen_report.UI_GROUPS:
                    self.assertIn(group, warnings.getvalue())
                self.assertIn("Valid UI areas: playback, places, browse, settings, timeline", warnings.getvalue())

    def test_only_the_head_commit_message_requests_the_walk(self):
        workflow = (pathlib.Path(screen_report.ROOT) / ".github/workflows/test.yml").read_text()
        self.assertIn("repos/$GITHUB_REPOSITORY/commits/$HEAD_SHA\" --jq '.commit.message'", workflow)
        self.assertNotIn('/commits" --jq', workflow)

    def test_only_requested_areas_block(self):
        _, matrix = screen_report.plan("pull_request", "", "Fix\n\n[ui: browse]\n")
        self.assertEqual(
            {e["group"]: e["required"] for e in matrix["include"]}, {"places-search": "true", "browse-pages": "true"}
        )

    def test_feature_release_requests_every_area_and_blocks(self):
        for title in ("Release Klassik 0.15.0", "[sz-123] Release Klassik 0.15.0", "Release Klassik 1.0"):
            for message in ("", "[ui: playback]"):
                with self.subTest(title=title, message=message):
                    _, matrix = screen_report.plan("pull_request", "", message, title)
                    required = {e["group"]: e["required"] for e in matrix["include"]}
                    self.assertEqual(len(required), len(screen_report.UI_GROUPS))
                    self.assertEqual(set(required.values()), {"true"})

    def test_patch_release_blocks_only_requested_areas(self):
        _, matrix = screen_report.plan(
            "pull_request", "", "[ui: browse]", "Release Klassik 0.16.1", project=self.project('"0.16.1"')
        )
        required = {e["group"]: e["required"] for e in matrix["include"]}
        self.assertEqual(required, {"places-search": "true", "browse-pages": "true"})

    def test_nightly_and_dispatch_walks_only_report(self):
        for args in (
            ("schedule", "", ""),
            ("workflow_dispatch", "all", ""),
        ):
            _, matrix = screen_report.plan(*args)
            self.assertTrue(matrix["include"])
            self.assertEqual({e["required"] for e in matrix["include"]}, {"false"}, args)

    def test_main_push_runs_no_walk(self):
        self.assertEqual(self.groups("push"), ("false", []))

    def test_nightly_and_ci_push_walk_everything(self):
        for event, ref in (("schedule", "refs/heads/main"), ("push", "refs/heads/ci")):
            ui, matrix = screen_report.plan(event, "", "", ref=ref)
            self.assertEqual(ui, "all")
            self.assertEqual(len(matrix["include"]), len(screen_report.UI_GROUPS))

    def test_release_title_walks_everything(self):
        for title in ("Release Klassik 0.15.0", "[sz-123] Release Klassik 0.15.0"):
            ui, matrix = screen_report.plan("pull_request", "", "", title)
            self.assertEqual(ui, "all")
            self.assertEqual(len(matrix["include"]), len(screen_report.UI_GROUPS))

    def test_unclear_release_versions_walk_everything(self):
        for title in ("Release Klassik 1.0", "Release Klassik 0.16.x", "Release Klassik ", "Release Klassik 0.16.00"):
            with self.subTest(title=title):
                self.assertEqual(screen_report.plan("pull_request", "", "[ui: browse]", title)[0], "all")

    @staticmethod
    def project(version):
        return (
            f'name: Klassik\nsettings:\n  base:\n    MARKETING_VERSION: {version}\n    CURRENT_PROJECT_VERSION: "1"\n'
        )

    def test_patch_release_walks_only_requested_areas(self):
        for title, version in (("Release Klassik 0.16.1", "0.16.1"), ("[sz-123] Release Klassik 0.16.10", "0.16.10")):
            with self.subTest(title=title), contextlib.redirect_stderr(io.StringIO()) as warnings:
                project = self.project(f'"{version}"')
                ui, matrix = screen_report.plan("pull_request", "", "Fix\n\n[ui: browse]\n", title, project=project)
                self.assertEqual(
                    (ui, [entry["group"] for entry in matrix["include"]]), ("browse", ["places-search", "browse-pages"])
                )
                self.assertEqual(warnings.getvalue(), "")

    def test_patch_release_without_request_warns(self):
        with contextlib.redirect_stderr(io.StringIO()) as warnings:
            project = self.project('"0.16.1"')
            self.assertEqual(
                screen_report.plan("pull_request", "", "", "Release Klassik 0.16.1", project=project)[0], "false"
            )
        self.assertIn("::warning::Patch release requests no walk areas.", warnings.getvalue())

    def test_patch_title_that_project_yml_does_not_prove_walks_everything(self):
        for project in (
            self.project('"0.17.0"'),
            self.project("0.16.1"),
            self.project('"0.16.1"') + '    MARKETING_VERSION: "0.17.0"\n',
            "",
        ):
            with self.subTest(project=project), contextlib.redirect_stderr(io.StringIO()) as warnings:
                ui, matrix = screen_report.plan(
                    "pull_request", "", "[ui: browse]", "Release Klassik 0.16.1", project=project
                )
                self.assertEqual((ui, len(matrix["include"])), ("all", len(screen_report.UI_GROUPS)))
                self.assertIn("::warning::Release title version 0.16.1 is not MARKETING_VERSION", warnings.getvalue())

    def test_plan_command_reads_project_yml_of_the_head(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory, "project.yml")
            path.write_text(self.project('"0.17.0"'))
            result = subprocess.run(
                [
                    sys.executable,
                    str(pathlib.Path(screen_report.__file__)),
                    "plan",
                    "pull_request",
                    "",
                    "Release Klassik 0.17.1",
                    "refs/pull/1/merge",
                    str(path),
                ],
                input="[ui: browse]\n",
                capture_output=True,
                text=True,
                check=True,
            )
        self.assertIn("ui=all\n", result.stdout)

    def test_release_launch_runs_except_on_pull_requests_that_are_no_release(self):
        for event in ("push", "schedule", "workflow_dispatch"):
            self.assertTrue(screen_report.release_launch(event))
        self.assertTrue(screen_report.release_launch("pull_request", "Release Klassik 0.21.0"))
        self.assertTrue(screen_report.release_launch("pull_request", "[sz-1] Release Klassik 0.21.1"))
        self.assertFalse(screen_report.release_launch("pull_request", "Fix the Release Klassik 0.21.0 notes"))
        self.assertFalse(screen_report.release_launch("pull_request", ""))

    def test_plan_command_prints_the_release_launch_flag(self):
        script = str(pathlib.Path(screen_report.__file__))
        for args, flag in ((["pull_request", "", "Fix"], "false"), (["push", ""], "true")):
            result = subprocess.run(
                [sys.executable, script, "plan", *args], input="", capture_output=True, text=True, check=True
            )
            self.assertIn(f"release_launch={flag}\n", result.stdout)

    def test_other_titles_are_not_releases(self):
        self.assertEqual(screen_report.plan("pull_request", "", "", "Fix the Release Klassik 0.16.0 notes")[0], "false")

    def test_shards_of_a_class_cover_every_method_and_screenshot_once(self):
        source = screen_report.WALK.read_text()
        for area in {area for areas in screen_report.SHARDS.values() for area in areas}:
            name = screen_report.area_class(area)
            groups = [group for group, areas in screen_report.UI_GROUPS.items() if area in areas.split(",")]
            entries = [screen_report.group_tests(group, area) for group in groups]
            with self.subTest(area=area):
                flat = [entry for shard in entries for entry in shard]
                self.assertEqual(len(flat), len(set(flat)))
                methods = screen_report.class_methods(source, name)
                self.assertEqual(set(flat), {f"{name}/{method}" for method in methods})
                shots = [set(screen_report.expected(source, area, shard)) for shard in entries]
                self.assertTrue(all(shots))
                self.assertEqual(sum(len(shard) for shard in shots), len(set().union(*shots)))
                self.assertEqual(set().union(*shots), set(screen_report.expected(source, area)))

    def test_every_listed_shard_method_exists(self):
        source = screen_report.WALK.read_text()
        for group, areas in screen_report.SHARDS.items():
            for area, methods in areas.items():
                with self.subTest(group=group, area=area):
                    self.assertLessEqual(methods, screen_report.class_methods(source, screen_report.area_class(area)))

    def test_a_shard_runs_only_the_requested_areas(self):
        self.assertEqual(screen_report.group_tests("places-search", "places"), ["PlacesScreens"])
        browse = screen_report.group_tests("places-search", "browse")
        self.assertTrue(browse)
        self.assertTrue(all(entry.startswith("BrowseScreens/") for entry in browse))
        self.assertEqual(screen_report.group_tests("browse-pages", "places"), [])
        self.assertEqual(screen_report.group_tests("settings-timeline"), ["SettingsScreens", "TimelineScreens"])

    def test_each_shard_requires_only_its_own_screenshots(self):
        source = screen_report.WALK.read_text()
        with tempfile.TemporaryDirectory() as directory:
            reports = pathlib.Path(directory)
            for group in screen_report.UI_GROUPS:
                report = reports / f"walk-{group}"
                report.mkdir()
                (report / "results.txt").write_text("build=passed\nui=passed\n")
                for name in screen_report.expected(source, "all", screen_report.group_tests(group)):
                    (report / f"{name}.png").touch()
            self.assertEqual(screen_report.aggregate_ui(reports, "all", source), "passed")
            missing = next((reports / "walk-browse-pages").glob("*.png"))
            missing.unlink()
            self.assertEqual(screen_report.unexplained_gaps(reports, "all", source), {"browse-pages": [missing.stem]})

    def test_run_by_hand_takes_the_input(self):
        self.assertEqual(
            self.groups("workflow_dispatch"),
            ("all", list(screen_report.UI_GROUPS)),
        )
        self.assertEqual(self.groups("workflow_dispatch", "Settings"), ("settings", ["settings-timeline"]))
        self.assertEqual(self.groups("workflow_dispatch", "false"), ("false", []))
        with self.assertRaises(ValueError):
            screen_report.plan("workflow_dispatch", "brwse", "")


class WarningReportTests(unittest.TestCase):
    def test_counts_each_warning_once_across_logs(self):
        a = "/Users/r/Klassik/A.swift:12:3: warning: 'x' is deprecated\nBuild ok\n"
        b = a + "/Users/r/Klassik/B.swift:7:1: warning: unused\nnote: not: warning: here\n"
        with tempfile.TemporaryDirectory() as tmp:
            one, two = pathlib.Path(tmp) / "build.log", pathlib.Path(tmp) / "unit.log"
            one.write_text(a)
            two.write_text(b)
            text, count = screen_report.warning_report([one, two, pathlib.Path(tmp) / "none.log"])
        self.assertEqual(count, 2)
        self.assertIn("2 compiler warnings", text)
        self.assertIn("No build log: none.log", text)

    def test_clean_log_counts_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = pathlib.Path(tmp) / "build.log"
            log.write_text("** BUILD SUCCEEDED **\n")
            self.assertEqual(screen_report.warning_report([log])[1], 0)

    def test_command_reports_and_exits_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = pathlib.Path(tmp) / "build.log"
            log.write_text("/a/B.swift:1:2: warning: w\n")
            run = subprocess.run(
                [sys.executable, str(pathlib.Path(screen_report.__file__)), "warnings", str(log)],
                capture_output=True,
                text=True,
            )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("::notice::Build warnings: 1", run.stdout)


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

    def test_the_fallback_is_the_nightly_walk_on_main(self):
        query = screen_baseline.runs_query("o/r", screen_baseline.FALLBACK, "success", screen_baseline.FALLBACK_EVENT)
        self.assertIn("branch=main&status=success", query)
        self.assertTrue(query.endswith("&event=schedule"))
        self.assertNotIn("event=", screen_baseline.runs_query("o/r", "topic", "completed"))

    def test_usable_needs_screenshots(self):
        screens = {"name": "screens", "expired": False, "size_in_bytes": 2_000_000}
        self.assertTrue(screen_baseline.usable([screens]))
        self.assertFalse(screen_baseline.usable([{**screens, "size_in_bytes": 1_300}]))
        self.assertFalse(screen_baseline.usable([{**screens, "expired": True}]))
        self.assertFalse(screen_baseline.usable([{**screens, "name": "screens-diff"}]))
        self.assertFalse(screen_baseline.usable([]))


if __name__ == "__main__":
    unittest.main()
