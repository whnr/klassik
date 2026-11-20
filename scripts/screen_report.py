"""Reports the result of a test run and of the screenshot comparison, for the job summary.

Usage:
    python3 scripts/screen_report.py plan <event> <dispatch-input> [<pr-title> <ref>] < <commit-messages>
        Prints the UI areas of the run and the matrix of the walk job, for GITHUB_OUTPUT.
    python3 scripts/screen_report.py select <requested-areas> <group-areas>
        Prints the selected areas and rejects unknown names.
    python3 scripts/screen_report.py aggregate-ui <reports-dir> <requested-areas>
        Prints the UI result. Fails if a selected group has no completed result, or passed without all its
        screenshots.
    python3 scripts/screen_report.py summary <screens-dir>
        Prints the results of scripts/screens.sh as Markdown and writes <screens-dir>/missing.txt.
    python3 scripts/screen_report.py retries <raw-log>
        Prints failed test names, attempt counts, outcomes, and first failures before log formatting.
    python3 scripts/screen_report.py console <console-file>...
        Prints, for each console of a test process, the count of lines that point to a crash or a runtime warning.
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
    """The screenshots that a walk of the areas in `ui` takes, from the snap calls of each area class."""
    if ui in ("", "false"):
        return []
    areas = None if ui in ("true", "all") else {a.strip().lower() for a in ui.split(",") if a.strip()}
    names, area, method = [], None, None
    for line in source.splitlines():
        if match := re.match(r"\s*(?:final )?class (\w+)", line):
            name = match.group(1)
            area = name[: -len("Screens")].lower() if name.endswith("Screens") else None
            method = None
        elif match := re.search(r"\bfunc (\w+)\(", line):
            method = match.group(1)
        elif match := re.search(r'\bsnap\(app, "([\w-]+)"\)', line):
            owner = area or SHARED_SNAPS.get(match.group(1))
            if owner and (areas is None or owner in areas) and (tests is None or method in tests):
                names.append(match.group(1))
    return sorted(set(names))


def read_results(text):
    """The last value of each key in results.txt."""
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


UI_GROUPS = {
    "playback-queue": "playback",
    "playback-controls": "playback",
    "places-browse": "places,browse",
    "settings-timeline": "settings,timeline",
}


# Balance playback by measured duration, because method counts hide the longer navigation tests.
PLAYBACK_QUEUE = {
    "testFavouriteRecordingOrder",
    "testOverlayLeavesThroughChronology",
    "testQueue",
    "testRecording",
    "testWorkPlayUsesTheContentInsetsOnEitherSide",
    "testNextEndsAtTheLastMovement",
}


def group_tests(group, source=None):
    if not group.startswith("playback-"):
        return None
    source = WALK.read_text() if source is None else source
    playback = re.search(r"class PlaybackScreens:.*?(?=\n(?:final )?class |\Z)", source, re.DOTALL)
    if playback is None:
        return []
    playback = playback.group()
    methods = set(re.findall(r"func (test\w+)\(", playback))
    if missing := PLAYBACK_QUEUE - methods:
        raise ValueError("Missing playback methods: " + ", ".join(sorted(missing)))
    return sorted(PLAYBACK_QUEUE if group == "playback-queue" else methods - PLAYBACK_QUEUE)


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


def requested_areas(messages):
    """The union of the "[ui: <areas>]" lines in the commit messages of a pull request, or "false"."""
    known = list(dict.fromkeys(area for areas in UI_GROUPS.values() for area in areas.split(",")))
    wanted, everything = set(), False
    for match in UI_REQUEST.finditer(messages):
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


def release_walk(title):
    """True if a pull request with `title` walks every group: a feature release. A patch release (x.y.z, z > 0)
    walks only the areas that its commits request. A release title without a clear version walks everything."""
    match = RELEASE_TITLE.match(title)
    return bool(match) and not PATCH_VERSION.fullmatch(match.group(1))


def plan(event, dispatch_input, messages, title="", ref="refs/heads/main"):
    """Feature release requests and nightly runs walk everything. Main pushes run no walk."""
    if event == "pull_request":
        ui = requested_areas(messages)
        if release_walk(title):
            ui = "all"
    elif event == "workflow_dispatch":
        ui = dispatch_input.replace(" ", "").lower() or "all"
        selected_areas(ui, "")
    elif event == "push" and ref == "refs/heads/main":
        ui = "false"
    else:
        ui = "all"
    include = []
    for group, areas in UI_GROUPS.items():
        if selected_areas(ui, areas) != "false":
            include.append({"group": group, "areas": areas, "tests": ",".join(group_tests(group) or [])})
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
        if missing := sorted(set(expected(source, selected, group_tests(group, source))) - captured):
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


def retry_report(log):
    """Read completion records before xcbeautify hides failed attempts."""
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
        print(retry_report(pathlib.Path(args[1]).read_text()))
        return
    if command == "console":
        print(console_report(args[1:]))
        return
    if command == "plan":
        ui, matrix = plan(args[1], args[2], sys.stdin.read(), *args[3:5])
        print(f"ui={ui}")
        print("matrix=" + json.dumps(matrix, separators=(",", ":")))
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
