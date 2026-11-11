"""Collects the baseline for scripts/screen_diff.py: each screen as the newest usable run saw it.

Runs on the branch of this run come first, so a branch is compared with its own last walk. Green runs on branch ci
follow. A run that walked only some areas holds only their screens, so older runs fill the rest.
A run is usable when its artifact "screens" holds screenshots. This run is never its own baseline.
Writes the PNGs and sources.json ({"<screen>.png": "run <id>, <commit>, <branch>"}) into the baseline directory.
Usage: GH_TOKEN=... GITHUB_REPOSITORY=owner/repo GITHUB_RUN_ID=... BASELINE_BRANCH=... \
    python3 scripts/screen_baseline.py <current-dir> <baseline-dir>
"""

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

RUNS = 30  # Most pushes walk no screens; their artifact holds only the gapless report.
FALLBACK = "ci"


def gh(*args):
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout


def candidates(branch_runs, fallback_runs, this_run):
    """The runs to try, in order: the branch of this run, then the fallback branch. Never this run, never one twice."""
    seen, out = {this_run}, []
    for run in [*branch_runs, *fallback_runs]:
        if run["id"] not in seen:
            seen.add(run["id"])
            out.append(run)
    return out


def usable(artifacts):
    """An artifact with the gapless report alone is small. One with screenshots is not."""
    return any(a["name"] == "screens" and not a["expired"] and a["size_in_bytes"] > 100_000 for a in artifacts)


def runs_of(repo, branch, status):
    query = f"repos/{repo}/actions/workflows/test.yml/runs?branch={branch}&status={status}&per_page={RUNS}"
    return json.loads(gh("api", query))["workflow_runs"]


def main(current_dir, base_dir):
    base_dir.mkdir(parents=True, exist_ok=True)
    repo, this_run = os.environ["GITHUB_REPOSITORY"], int(os.environ.get("GITHUB_RUN_ID", 0))
    branch = os.environ.get("BASELINE_BRANCH", FALLBACK)
    # A walk with a tolerated UI failure, or a run that failed after the walk, still holds real screens.
    branch_runs = runs_of(repo, branch, "completed") if branch != FALLBACK else []
    wanted = {p.name for p in current_dir.glob("*.png")}
    sources = {}
    for run in candidates(branch_runs, runs_of(repo, FALLBACK, "success"), this_run):
        if not wanted - set(sources):
            break
        artifacts = json.loads(gh("api", f"repos/{repo}/actions/runs/{run['id']}/artifacts"))["artifacts"]
        if not usable(artifacts):
            continue
        with tempfile.TemporaryDirectory() as tmp:
            gh("run", "download", str(run["id"]), "-R", repo, "-n", "screens", "-D", tmp)
            for png in pathlib.Path(tmp).glob("*.png"):
                if png.name in wanted and png.name not in sources:
                    shutil.copy(png, base_dir / png.name)
                    sources[png.name] = f"run {run['id']}, {run['head_sha'][:7]}, {run['head_branch']}"
    (base_dir / "sources.json").write_text(json.dumps(sources, indent=1))
    print(f"Baseline for {len(sources)} of {len(wanted)} screens")


if __name__ == "__main__":
    main(*map(pathlib.Path, sys.argv[1:3]))
