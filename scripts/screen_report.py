"""Reports the result of a test run and of the screenshot comparison, for the job summary.

Usage:
    python3 scripts/screen_report.py summary <screens-dir>
        Prints the results of scripts/screens.sh as Markdown and writes <screens-dir>/missing.txt.
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


def expected(source, ui):
    """The screenshots that a walk of the areas in `ui` takes, from the snap calls of each area class."""
    if ui in ("", "false"):
        return []
    areas = None if ui in ("true", "all") else {a.strip().lower() for a in ui.split(",") if a.strip()}
    names, area = [], None
    for line in source.splitlines():
        if match := re.match(r"\s*(?:final )?class (\w+)Screens\b", line):
            area = match.group(1).lower()
        elif (match := re.search(r'\bsnap\(app, "([\w-]+)"\)', line)) and area and (areas is None or area in areas):
            names.append(match.group(1))
    return sorted(set(names))


def read_results(text):
    """The last value of each key in results.txt."""
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


def ui_result(results):
    """The UI line of the summary. A tolerated failure must read as a failure."""
    state = results.get("ui", "not run")
    if state != "failed":
        return state
    if results.get("ui_required") == "true":
        return "**FAILED** (blocks the run: `UI_TESTS_REQUIRED=true`)"
    return "**FAILED, tolerated** (`UI_TESTS_REQUIRED` is not `true`)"


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
    command, screens = args[0], pathlib.Path(args[1])
    if command == "summary":
        results_file = screens / "results.txt"
        results = read_results(results_file.read_text()) if results_file.exists() else {}
        wanted = expected(WALK.read_text(), results.get("ui_areas", "false"))
        captured = [p.stem for p in screens.glob("*.png")]
        run = "{GITHUB_SERVER_URL}/{GITHUB_REPOSITORY}/actions/runs/{GITHUB_RUN_ID}#artifacts"
        url = run.format(**os.environ) if "GITHUB_RUN_ID" in os.environ else ""
        text, missing = summary(results, captured, wanted, url)
        (screens / "missing.txt").write_text("".join(name + "\n" for name in missing))
        print(text)
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
