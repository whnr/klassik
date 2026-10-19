"""Collects the baseline for scripts/screen_diff.py: each screen as the newest green run on branch ci saw it.

A run that walked only some areas holds only their screens, so older runs fill the rest.
Writes the PNGs and sources.json ({"<screen>.png": "run <id>, <commit>"}) into the baseline directory.
Usage: GH_TOKEN=... GITHUB_REPOSITORY=owner/repo GITHUB_RUN_ID=... python3 scripts/screen_baseline.py <current-dir> <baseline-dir>
"""
import json, os, pathlib, shutil, subprocess, sys, tempfile

RUNS = 30  # Most pushes walk no screens; their artifact holds only the gapless report.


def gh(*args):
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout


current_dir, base_dir = map(pathlib.Path, sys.argv[1:3])
base_dir.mkdir(parents=True, exist_ok=True)
repo, this_run = os.environ["GITHUB_REPOSITORY"], int(os.environ.get("GITHUB_RUN_ID", 0))
wanted = {p.name for p in current_dir.glob("*.png")}
sources = {}
runs = json.loads(
    gh("api", f"repos/{repo}/actions/workflows/test.yml/runs?branch=ci&status=success&per_page={RUNS}")
)["workflow_runs"]
for run in runs:
    if not wanted - set(sources):
        break
    if run["id"] == this_run:
        continue
    artifacts = json.loads(gh("api", f"repos/{repo}/actions/runs/{run['id']}/artifacts"))["artifacts"]
    if not any(a["name"] == "screens" and not a["expired"] and a["size_in_bytes"] > 100_000 for a in artifacts):
        continue
    with tempfile.TemporaryDirectory() as tmp:
        gh("run", "download", str(run["id"]), "-R", repo, "-n", "screens", "-D", tmp)
        for png in pathlib.Path(tmp).glob("*.png"):
            if png.name in wanted and png.name not in sources:
                shutil.copy(png, base_dir / png.name)
                sources[png.name] = f"run {run['id']}, {run['head_sha'][:7]}"
(base_dir / "sources.json").write_text(json.dumps(sources, indent=1))
print(f"Baseline for {len(sources)} of {len(wanted)} screens")
