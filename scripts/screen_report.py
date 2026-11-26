"""Reports the result of a test run and of the screenshot comparison, for the job summary.

Usage:
    python3 scripts/screen_report.py plan <event> <dispatch-input> [<pr-title> <ref> [<project.yml>]] < <message>
        Prints the UI areas of the run, the matrix of the walk job and whether the Release launch check runs, for
        GITHUB_OUTPUT. <message> is the commit message of the PR head, and <project.yml> is the file at the PR head.
    python3 scripts/screen_report.py select <requested-areas> <group-areas>
        Prints the selected areas and rejects unknown names.
    python3 scripts/screen_report.py aggregate-ui <reports-dir> <requested-areas>
        Prints the UI result. Fails if a selected group has no completed result, or passed without all its
        screenshots.
    python3 scripts/screen_report.py summary <screens-dir>
        Prints the results of scripts/screens.sh as Markdown and writes <screens-dir>/missing.txt.
    python3 scripts/screen_report.py retries <raw-log>
        Prints failed test names, attempt counts, outcomes, and first failures before log formatting.
    python3 scripts/screen_report.py retry-plan <tests.json>
        Reads `xcresulttool get test-results tests`. Prints the failed tests that the simulator or runner failed, one
        Target/Class/method per line, or ALL when the bundle holds no test. Prints nothing when nothing may be retried.
        Any error exits 2.
    python3 scripts/screen_report.py assertion-failures <tests.json>
        Prints the failed tests that are not an infrastructure failure. Any error exits 2, so a caller fails closed.
    python3 scripts/screen_report.py expected-tests <enumeration.json>
        Prints the tests of `xcodebuild -enumerate-tests` output, one Class/method per line.
    python3 scripts/screen_report.py unrun <expected.txt> <target> <tests.json>
        Prints the expected tests that the bundle holds no result for, one Target/Class/method per line.
    python3 scripts/screen_report.py unfinished <expected.txt> <tests.json>...
        Prints the expected tests with no passed result. A later bundle replaces an earlier one. Exits 2 on any error.
    python3 scripts/screen_report.py console <console-file>...
        Prints, for each console of a test process, the count of lines that point to a crash or a runtime warning.
    python3 scripts/screen_report.py warnings <build-log>...
        Prints the number of distinct compiler warnings in xcodebuild logs as Markdown, and a ::notice:: line. It never
        fails on a count: the number reports, it does not gate. A missing log is reported, not an error.
    python3 scripts/screen_report.py diff <screens-dir> <diff-dir> [<baseline-dir>]
        Prints the counts of scripts/screen_diff.py as Markdown.
"""

import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
WALK = ROOT / "KlassikUITests" / "ScreensTests.swift"


# A snap in a shared class has no area of its own; only the Places walk connects with a screenshot.
SHARED_SNAPS = {"01-connect": "places"}


def expected(source, ui, tests=None):
    """The screenshots that a walk of the areas in `ui` takes, from the snap calls of each area class.
    `tests` holds the -only-testing entries of a shard (see group_tests), or None for whole classes."""
    if ui in ("", "false"):
        return []
    areas = None if ui in ("true", "all") else {a.strip().lower() for a in ui.split(",") if a.strip()}
    names, area, name, method = [], None, None, None
    for line in source.splitlines():
        if match := re.match(r"\s*(?:final )?class (\w+)", line):
            name = match.group(1)
            area = name[: -len("Screens")].lower() if name.endswith("Screens") else None
            method = None
        elif match := re.search(r"\bfunc (\w+)\(", line):
            method = match.group(1)
        elif match := re.search(r'\bsnap\(app, "([\w-]+)"\)', line):
            owner = area or SHARED_SNAPS.get(match.group(1))
            if not owner or (areas is not None and owner not in areas):
                continue
            # A shared snap belongs to the walk of its whole owner class.
            entries = {area_class(owner)} if area is None else {name, f"{name}/{method}"}
            if tests is None or entries & set(tests):
                names.append(match.group(1))
    return sorted(set(names))


def read_results(text):
    """The last value of each key in results.txt."""
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


UI_GROUPS = {
    "playback-queue": "playback",
    "playback-overlay": "playback",
    "playback-controls": "playback",
    "places-search": "places,browse",
    "browse-pages": "browse",
    "settings-timeline": "settings,timeline",
}


# Shards share a class by measured duration, because method counts hide the longer navigation tests.
# A group that lists no methods for an area runs the methods that no other group lists, so a new or renamed test
# always runs. scripts/test_screens.py refuses a listed method that ScreensTests.swift does not have.
SHARDS = {
    "playback-queue": {
        "playback": {
            "testFavouriteRecordingOrderIgnoresDrag",
            "testOverlayLeavesThroughChronology",
            "testQueue",
            "testRecording",
            "testWorkPlayUsesTheContentInsetsOnEitherSide",
            "testNextEndsAtTheLastMovement",
        }
    },
    "playback-overlay": {
        "playback": {
            "testAlbumWorkHasOneDisclosureOnThePageAndOverlay",
            "testOverlayLeavesThroughLibrary",
            "testOverlayLeavesThroughSearch",
            "testOverlayLinkUsesTheUnderlyingStack",
            "testOverlayOnTheLeft",
            "testOverlayOpensAndSlidesDown",
            "testPageMenus",
            "testPlayerFollowsAfterQuietSpell",
            "testPlayOnTheWorkPage",
            "testPlayWholeAlbumOnTheRecordingPage",
            "testPlayingRowNamesLinkFromTheOverlay",
            "testQueueEndsHere",
            "testSlowConnectionLine",
            "testStopClosesThePlayer",
            "testSwipeDownClosesThePlayer",
        }
    },
    "places-search": {
        "browse": {
            "testRecentSearches",
            "testSearch",
            "testSearchFilters",
            "testSearchSections",
            "testSearchSheetBackAndDimming",
            "testSwipeDownClosesTheFilterSheet",
        }
    },
}


def area_class(area):
    return area[:1].upper() + area[1:] + "Screens"


def class_methods(source, name):
    body = re.search(rf"class {name}:.*?(?=\n(?:final )?class |\Z)", source, re.DOTALL)
    return set(re.findall(r"func (test\w+)\(", body.group())) if body else set()


def group_tests(group, request="all", source=None):
    """The -only-testing entries of `group` for the requested areas: a whole class, or Class/method where groups
    share the class."""
    selected = selected_areas(request, UI_GROUPS[group])
    if selected == "false":
        return []
    source = WALK.read_text() if source is None else source
    entries = []
    for area in selected.split(","):
        name = area_class(area)
        shards = [areas[area] for areas in SHARDS.values() if area in areas]
        if not shards:
            entries.append(name)
            continue
        methods = class_methods(source, name)
        own = SHARDS.get(group, {}).get(area)
        wanted = methods & own if own is not None else methods - set().union(*shards)
        entries += [f"{name}/{method}" for method in sorted(wanted)]
    return entries


def selected_areas(request, available):
    request = request.replace(" ", "").lower() or "all"
    known = {area for areas in UI_GROUPS.values() for area in areas.split(",")}
    if request in ("all", "true"):
        return available
    if request == "false":
        return "false"
    requested = set(request.split(","))
    if unknown := requested - known:
        raise ValueError("Unknown UI areas: " + ", ".join(sorted(unknown)))
    return ",".join(area for area in available.split(",") if area in requested) or "false"


UI_REQUEST = re.compile(r"^\s*\[ui:([^\]]*)\]\s*$", re.IGNORECASE | re.MULTILINE)


def requested_areas(message):
    """The union of the "[ui: <areas>]" lines in the commit message of the PR head, or "false".
    Earlier commits do not count, so only the push that asks for the walk runs it."""
    known = list(dict.fromkeys(area for areas in UI_GROUPS.values() for area in areas.split(",")))
    wanted, everything = set(), False
    for match in UI_REQUEST.finditer(message):
        request = match.group(1).replace(" ", "").lower()
        if request in ("", "false"):
            continue
        if request not in ("all", "true"):
            areas = set(request.split(","))
            if unknown := areas - set(known):
                print(
                    "::warning::Ignoring unknown UI areas: "
                    + ", ".join(sorted(unknown))
                    + ". Valid UI areas: "
                    + ", ".join(known)
                    + ". UI_GROUPS: "
                    + ", ".join(UI_GROUPS),
                    file=sys.stderr,
                )
            wanted |= areas & set(known)
        else:
            wanted |= set(known)
        if request in ("all", "true"):
            everything = True
    if everything:
        return "all"
    return ",".join(area for area in known if area in wanted) or "false"


RELEASE_TITLE = re.compile(r"^(?:\[[^]]+\] )?Release Klassik (\S*)")
PATCH_VERSION = re.compile(r"[0-9]+\.[0-9]+\.0*[1-9][0-9]*")
PROJECT_VERSION = re.compile(r"^ *MARKETING_VERSION:(.*)$", re.MULTILINE)


def project_version(project):
    """The one MARKETING_VERSION in the text of project.yml, or None if it is not exactly one quoted value."""
    values = {value.strip() for value in PROJECT_VERSION.findall(project)}
    if len(values) != 1 or not re.fullmatch(r'"[^"]+"', value := values.pop()):
        return None
    return value[1:-1]


def release_walk(title, project=""):
    """ "all" if a pull request with `title` walks every group: a feature release. "patch" if it walks only the
    areas that its head commit requests. None if it is no release.

    A patch release has the version x.y.z (z > 0) in its title and as MARKETING_VERSION in `project`, the
    project.yml of the PR head. Every other release title walks everything, because the title alone does
    not prove what the release builds.
    """
    match = RELEASE_TITLE.match(title)
    if not match:
        return None
    version = match.group(1)
    if not PATCH_VERSION.fullmatch(version):
        return "all"
    if (built := project_version(project)) != version:
        print(
            f"::warning::Release title version {version} is not MARKETING_VERSION {built} of project.yml. "
            "Walking everything.",
            file=sys.stderr,
        )
        return "all"
    return "patch"


def release_launch(event, title=""):
    """The Release launch check runs on nightly and manual runs and on a pull request that is a release. A push to
    main does not run it: the release PR head run proves it for the TestFlight gate (scripts/green_test_gate.py)."""
    if event == "pull_request":
        return RELEASE_TITLE.match(title) is not None
    return event in ("schedule", "workflow_dispatch")


def plan(event, dispatch_input, message, title="", ref="refs/heads/main", project=""):
    """Feature release requests and nightly runs walk everything. Main pushes run no walk.
    `message` is the commit message of the PR head, and `project` is the text of project.yml at the PR head."""
    asked = "false"
    if event == "pull_request":
        ui = asked = requested_areas(message)
        release = release_walk(title, project)
        if release == "all":
            ui = asked = "all"
        elif release == "patch" and ui == "false":
            print("::warning::Patch release requests no walk areas. Add a [ui: <areas>] line.", file=sys.stderr)
    elif event == "workflow_dispatch":
        ui = dispatch_input.replace(" ", "").lower() or "all"
        selected_areas(ui, "")
    elif event == "push" and ref == "refs/heads/main":
        ui = "false"
    else:
        ui = "all"
    include = []
    for group, areas in UI_GROUPS.items():
        if tests := group_tests(group, ui):
            # A group blocks the run when the PR asked for one of its areas: the head commit, or a release title that
            # walks everything. A walk that the nightly run or a manual run starts reports only.
            required = selected_areas(asked, areas) != "false"
            include.append(
                {"group": group, "areas": areas, "tests": ",".join(tests), "required": "true" if required else "false"}
            )
    return ui, {"include": include}


def unexplained_gaps(reports, request, source):
    """The screenshots that each passed group did not take, by group.

    A failed group explains its own gaps: the summary lists them, and UI_TESTS_REQUIRED decides if they block.
    A passed group has no such explanation, for example when the export of its attachments failed.
    """
    gaps = {}
    for group, areas in UI_GROUPS.items():
        selected = selected_areas(request, areas)
        if selected == "false":
            continue
        report = reports / f"walk-{group}"
        path = report / "results.txt"
        if not path.exists() or read_results(path.read_text()).get("ui") != "passed":
            continue
        captured = {p.stem for p in report.glob("*.png")}
        if missing := sorted(set(expected(source, selected, group_tests(group, request, source))) - captured):
            gaps[group] = missing
    return gaps


def aggregate_ui(reports, request, source=None):
    source = WALK.read_text() if source is None else source
    states = []
    for group, areas in UI_GROUPS.items():
        if selected_areas(request, areas) == "false":
            continue
        path = reports / f"walk-{group}" / "results.txt"
        results = read_results(path.read_text()) if path.exists() else {}
        state = results.get("ui")
        if results.get("build") != "passed" or state not in ("passed", "failed"):
            return "incomplete"
        states.append(state)
    if unexplained_gaps(reports, request, source):
        return "incomplete"
    return "failed" if "failed" in states else "passed" if states else "not run"


def ui_result(results):
    """The UI line of the summary. A tolerated failure must read as a failure."""
    state = results.get("ui", "not run")
    if state == "incomplete":
        return "**FAILED** (incomplete UI results)"
    if state != "failed":
        return state
    if results.get("ui_required") == "true":
        return "**FAILED** (blocks the run: `UI_TESTS_REQUIRED=true`)"
    return "**FAILED, tolerated** (`UI_TESTS_REQUIRED` is not `true`)"


# A message that proves the simulator or the test runner failed, not the code under test. A crash of the app under
# test is a real fault: it must not match, or a crash that does not repeat passes on the retry.
INFRASTRUCTURE = re.compile(
    r"Early unexpected exit|never finished bootstrapping|lost connection"
    r"|connection (?:was )?(?:interrupted|invalid)"
    r"|failed to (?:launch|boot|terminate|connect)|unable to (?:boot|launch|connect)"
    r"|test runner (?:hung|failed|exited|crashed)"
    r"|Application '[^']+' does not have a process ID"
    r"|CoreSimulator|simulator (?:device )?(?:failed|crashed|disconnected)|Mach error"
    r"|(?:testmanagerd|XCTRunner) .*crashed",
    re.IGNORECASE,
)


# Failures that count as a runner error, not a failed test: the simulator or runner broke while the app was idle, and
# no check inside the app failed. Each has a reason for the report. Every pattern here must also match INFRASTRUCTURE,
# so the failed test is retried. A failed check in the app never belongs here.
RUNNER_ERRORS = (
    (re.compile(r"Failed to terminate \S+", re.IGNORECASE), "the simulator could not terminate the app"),
    (
        re.compile(r"Application '[^']+' does not have a process ID", re.IGNORECASE),
        "the runner lost the app process, on a starved simulator",
    ),
)


def runner_error_reason(messages):
    """The named reason when every message is a known runner error, else None. One other failure message, such as an
    assertion before the teardown error, makes the attempt a failed test."""
    reasons = []
    for message in messages:
        found = next((reason for pattern, reason in RUNNER_ERRORS if pattern.search(message)), None)
        if not found:
            return None
        reasons.append(found)
    return reasons[0] if reasons else None


def failed_cases(tests):
    """The failed test cases of `xcresulttool get test-results tests` JSON: (identifier, messages) pairs, where the
    identifier is Target/Class/method for -only-testing."""
    found = []

    def walk(node, bundle):
        kind = node.get("nodeType", "")
        if kind in ("Unit test bundle", "UI test bundle"):
            bundle = node.get("name", "")
        if kind == "Test Case":
            if node.get("result") == "Failed":
                name = node.get("nodeIdentifier") or node.get("name", "")
                # XCTest methods are named test*; xcodebuild accepts them without the parentheses.
                if name.endswith("()") and name.rsplit("/", 1)[-1].startswith("test"):
                    name = name[:-2]
                messages = []

                def collect(child):
                    if child.get("nodeType") == "Failure Message":
                        messages.append(child.get("name", ""))
                    for grandchild in child.get("children", []):
                        collect(grandchild)

                collect(node)
                found.append((f"{bundle}/{name}" if bundle else name, messages))
            return
        for child in node.get("children", []):
            walk(child, bundle)

    for node in tests.get("testNodes", []):
        walk(node, "")
    return found


def has_cases(tests):
    def count(node):
        return (node.get("nodeType") == "Test Case") + sum(count(c) for c in node.get("children", []))

    return any(count(node) for node in tests.get("testNodes", []))


def infrastructure_failure(messages):
    """Only a message that names the simulator or runner earns a retry. A failure without a message does not."""
    return any(INFRASTRUCTURE.search(message) for message in messages)


def retry_plan(tests):
    """The tests to run once more, or None when no failed test may be retried. ["ALL"] if the bundle holds no test."""
    if not has_cases(tests):
        return ["ALL"]
    return [name for name, messages in failed_cases(tests) if infrastructure_failure(messages)] or None


def assertion_failures(tests):
    return [name for name, messages in failed_cases(tests) if not infrastructure_failure(messages)]


def test_key(identifier):
    """Class/method of an identifier such as Target/Class/method(), so enumeration and bundle forms compare."""
    parts = identifier.removesuffix("()").split("/")
    return "/".join(parts[-2:])


def enumerated_tests(enumeration):
    """The leaf test identifiers of `xcodebuild -enumerate-tests -test-enumeration-format json` output."""
    found = []

    def walk(node, enabled):
        if isinstance(node, dict):
            children = node.get("children") or []
            if enabled and isinstance(node.get("identifier"), str) and not children:
                found.append(test_key(node["identifier"]))
            for key, child in node.items():
                walk(child, enabled or key == "enabledTests")
        elif isinstance(node, list):
            for child in node:
                walk(child, enabled)

    walk(enumeration, False)
    return sorted(set(found))


def recorded_results(tests):
    """Class/method to result for every test case of a result bundle."""
    found = {}

    def walk(node):
        if node.get("nodeType") == "Test Case":
            found[test_key(node.get("nodeIdentifier") or node.get("name", ""))] = node.get("result", "")
        for child in node.get("children", []):
            walk(child)

    for node in tests.get("testNodes", []):
        walk(node)
    return found


def unrun_tests(expected, target, tests):
    """Expected tests that a bundle holds no result for: the runner ended before it reached them."""
    recorded = recorded_results(tests)
    return [f"{target}/{key}" for key in expected if key not in recorded]


# Results that need no further run. Failed and anything unknown do not count.
FINISHED = {"Passed", "Skipped", "Expected Failure"}


def unfinished_tests(expected, bundles):
    """Expected tests without a passed result once the bundles are laid over each other, the last bundle winning."""
    results = {}
    for tests in bundles:
        results.update(recorded_results(tests))
    return [key for key in expected if results.get(key) not in FINISHED]


def retry_report(log, run_attempt=1):
    """Read completion records before xcbeautify hides failed attempts. A manual job rerun (run_attempt above 1)
    counts as a retry, so the report says so."""
    attempts, issues = {}, {}
    active = None
    for number, line in enumerate(log.splitlines(), 1):
        if match := re.match(r"Test Case '(.+)' started\.", line):
            active = match[1]
        if "error:" in line and active:
            issues.setdefault(active, []).append(line.strip())
        if match := re.search(r"[✘] Test (.+?) recorded an issue (.+)", line):
            issues.setdefault(match[1], []).append(match[2])
        match = re.match(r"Test Case '(.+)' (passed|failed) \(", line)
        if not match:
            match = re.search(r"[✔✘] Test (.+?)(?: with \d+ test cases)? (passed|failed) after ", line)
        if match:
            name, state = match.groups()
            attempts.setdefault(name, []).append((state, number, issues.pop(name, []), line.strip()))
            if name == active:
                active = None
    lines = ["### Failed-test attempts", ""]
    if run_attempt > 1:
        lines += [f"**Manual rerun: run attempt {run_attempt}.** A manual rerun counts as a retry.", ""]
    failed = {name: runs for name, runs in attempts.items() if any(run[0] == "failed" for run in runs)}
    if not attempts:
        return "\n".join(lines + ["No completed test attempts recorded. Inspect the raw log and result bundle.", ""])
    if not failed:
        return "\n".join(lines + ["No failed test attempts recorded.", ""])
    lines += ["| Test | Attempts | Outcome | First failure |", "|---|---|---|---|"]
    for name, runs in failed.items():
        first = next(run for run in runs if run[0] == "failed")
        detail = "; ".join(first[2]) or first[3]
        outcome = "recovered" if runs[-1][0] == "passed" else "failed"
        cells = [name, str(len(runs)), outcome, f"line {first[1]}: {detail}"]
        lines.append("| " + " | ".join(cell.replace("|", "\\|") for cell in cells) + " |")
    recovered = {name: runs for name, runs in failed.items() if runs[-1][0] == "passed"}
    reasons = {}
    for name, runs in recovered.items():
        reason = runner_error_reason(next(run for run in runs if run[0] == "failed")[2])
        if reason:
            reasons[name] = reason
    flaky = [name for name in recovered if name not in reasons]
    if reasons:
        lines += [
            "",
            "**Runner error, retried** (not a failed test; the retry passed). A reviewer does not block on these:",
        ]
        lines += [f"- `{name}`: {reason}" for name, reason in reasons.items()]
    if flaky:
        lines += [
            "",
            "**Flaky** (failed once, passed on the retry after a simulator or runner failure). File a bead for each:",
        ]
        lines += [f"- `{name}`" for name in flaky]
    return "\n".join(lines) + "\n"


CONSOLE_SIGNS = re.compile(r"Fatal error|Thread|assert|runtime:")


def console_report(files):
    """One line for each console file: how many lines hold a sign of a crash or a runtime warning."""
    lines = ["### Test console", ""]
    files = [path for path in files if pathlib.Path(path).is_file()]
    for path in files:
        text = pathlib.Path(path).read_text(errors="replace")
        count = sum(1 for line in text.splitlines() if CONSOLE_SIGNS.search(line))
        lines.append(
            f"- `{pathlib.Path(path).name}`: {count} lines with `Fatal error`, `Thread`, `assert` or `runtime:`"
        )
    if not files:
        lines.append("No console file was exported.")
    return "\n".join(lines) + "\n"


# xcodebuild prints each warning in the build output and again in its summary, so the lines are counted once each.
COMPILER_WARNING = re.compile(r"^(?:/\S.*?|\S+\.\w+):\d+(?::\d+)?: warning: .+", re.MULTILINE)


def warning_report(files):
    """The number of distinct compiler warnings in the build logs. It reports and never gates."""
    found, missing = set(), []
    for path in files:
        if not pathlib.Path(path).is_file():
            missing.append(pathlib.Path(path).name)
            continue
        found.update(m.group(0) for m in COMPILER_WARNING.finditer(pathlib.Path(path).read_text(errors="replace")))
    lines = ["### Build warnings", "", f"{len(found)} compiler warnings."]
    if missing:
        lines.append(f"No build log: {', '.join(missing)}. The count is incomplete.")
    lines += ["", *(f"- `{w}`" for w in sorted(found)[:20])]
    if len(found) > 20:
        lines.append(f"- and {len(found) - 20} more in the log")
    return "\n".join(lines) + "\n", len(found)


def summary(results, captured, wanted, artifacts_url=""):
    missing = sorted(set(wanted) - set(captured))
    lines = [
        "## Test results",
        "",
        "| Check | Result |",
        "|---|---|",
        f"| Build | {results.get('build', 'not run')} |",
        f"| Unit tests | {results.get('unit', 'not run')} |",
        f"| UI tests | {ui_result(results)} |",
        f"| UI tests required | {'yes' if results.get('ui_required') == 'true' else 'no'} |",
        f"| UI areas | {results.get('ui_areas', 'false')} |",
        f"| Screenshots captured | {len(set(captured) & set(wanted))} of {len(wanted)} |",
        f"| Screenshots missing | {', '.join(missing) or 'none'} |",
    ]
    if wanted and not captured:
        lines += ["", "No screenshot exists, so the comparison does not run."]
    if artifacts_url:
        lines += ["", f"[Artifacts]({artifacts_url}): `screens`, and `screens-diff` after a comparison."]
    return "\n".join(lines) + "\n", missing


def diff_summary(report, missing, sources):
    """The counts of one comparison. `report` is diff.json, or None when the comparison did not run."""
    if report is None:
        return "## Screenshot comparison\n\nSkipped: the comparison wrote no report.\n"
    bands = [r["band"] for r in report.values()]
    changed = bands.count("large") + bands.count("small")
    used = sorted(set(sources.values()))
    lines = [
        "## Screenshot comparison",
        "",
        f"Baseline: {'; '.join(used) if used else 'none found, so every screen is new'}.",
        "",
        "| Added | Changed | Unchanged | Missing |",
        "|---|---|---|---|",
        f"| {bands.count('new')} | {changed} ({bands.count('large')} large) | {bands.count('same')} | {len(missing)} |",
    ]
    if missing:
        lines += ["", "Missing in this run: " + ", ".join(missing) + "."]
    return "\n".join(lines) + "\n"


def read_lines(path):
    return path.read_text().split() if path.exists() else []


def main(args):
    command = args[0]
    if command == "retries":
        attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
        print(retry_report(pathlib.Path(args[1]).read_text(), int(attempt) if attempt.isdigit() else 1))
        return
    if command in ("retry-plan", "assertion-failures", "expected-tests", "unrun", "unfinished"):
        # Exit 0 whatever the answer, and 2 on any error: a traceback exits 1, which a caller could read as "none".
        try:

            def read(path):
                return json.loads(pathlib.Path(path).read_text() or "{}")

            def lines(path):
                return pathlib.Path(path).read_text().split()

            if command == "retry-plan":
                found = retry_plan(read(args[1])) or []
            elif command == "assertion-failures":
                found = assertion_failures(read(args[1]))
            elif command == "expected-tests":
                found = enumerated_tests(read(args[1]))
                if not found:
                    raise ValueError("the enumeration holds no test")
            elif command == "unrun":
                found = unrun_tests(lines(args[1]), args[2], read(args[3]))
            else:
                found = unfinished_tests(lines(args[1]), [read(path) for path in args[2:]])
        except Exception as error:
            print(f"{command}: {error}", file=sys.stderr)
            sys.exit(2)
        if found:
            print("\n".join(found))
        return
    if command == "console":
        print(console_report(args[1:]))
        return
    if command == "warnings":
        text, count = warning_report(args[1:])
        print(f"::notice::Build warnings: {count}")
        print(text)
        return
    if command == "plan":
        project = pathlib.Path(args[5]).read_text() if len(args) > 5 else ""
        ui, matrix = plan(args[1], args[2], sys.stdin.read(), *args[3:5], project=project)
        print(f"ui={ui}")
        print("matrix=" + json.dumps(matrix, separators=(",", ":")))
        print("ui_required=" + str(any(g["required"] == "true" for g in matrix["include"])).lower())
        print("release_launch=" + str(release_launch(args[1], args[3] if len(args) > 3 else "")).lower())
        return
    if command == "select":
        print(selected_areas(args[1], args[2]))
        return
    if command == "aggregate-ui":
        reports = pathlib.Path(args[1])
        state = aggregate_ui(reports, args[2])
        for group, missing in unexplained_gaps(reports, args[2], WALK.read_text()).items():
            print(f"::error::walk-{group} passed without screenshots: {', '.join(missing)}", file=sys.stderr)
        print(f"ui={state}")
        sys.exit(1 if state == "incomplete" else 0)
    screens = pathlib.Path(args[1])
    if command == "summary":
        results_file = screens / "results.txt"
        results = read_results(results_file.read_text()) if results_file.exists() else {}
        methods = results.get("ui_methods", "")
        wanted = expected(WALK.read_text(), results.get("ui_areas", "false"), methods.split(",") if methods else None)
        captured = [p.stem for p in screens.glob("*.png")]
        run = "{GITHUB_SERVER_URL}/{GITHUB_REPOSITORY}/actions/runs/{GITHUB_RUN_ID}#artifacts"
        url = run.format(**os.environ) if "GITHUB_RUN_ID" in os.environ else ""
        text, missing = summary(results, captured, wanted, url)
        (screens / "missing.txt").write_text("".join(name + "\n" for name in missing))
        print(text)
        for report in sorted(screens.glob("*-retries.txt")):
            print(f"\n#### {report.stem}\n")
            print(report.read_text())
    elif command == "diff":
        diff_dir = pathlib.Path(args[2])
        report_file = diff_dir / "diff.json"
        sources_file = pathlib.Path(args[3]) / "sources.json" if len(args) > 3 else None
        sources = json.loads(sources_file.read_text()) if sources_file and sources_file.exists() else {}
        report = json.loads(report_file.read_text()) if report_file.exists() else None
        print(diff_summary(report, read_lines(screens / "missing.txt"), sources))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
