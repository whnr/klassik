"""Decides if the Lab workflow must build, and finds the green Lab run that covers a commit.

The Lab builds KlassikLab and KlassikLabTests on the engine. A version bump in project.yml changes none of that,
so a release commit needs no Lab build. `needs_lab` is the one rule for both uses:
  plan <base> <head>  prints `run=true` or `run=false` for a change. Any doubt prints `run=true`.
  gate <sha>          prints the SHA of the green Lab run that covers <sha>: its own, or that of the newest
                      ancestor when every commit since then needs no Lab build. Exit 1 gives the reason.
A Lab run counts as green only when its `lab` job passed. A run whose job was skipped proves nothing.

Usage: GH_TOKEN=... GITHUB_REPOSITORY=owner/repo python3 scripts/lab_plan.py plan <base> <head>
"""

import json
import os
import sys

import green_test_gate as gate

# What the Lab build reads. The paths filter of lab.yml lists the same paths, and project.yml besides.
LAB_PATHS = ("KlassikLab/", "KlassikLabTests/", "KlassikEngine/")
LAB_FILES = (".github/workflows/lab.yml",)
REQUIRED_JOBS = ("lab",)
ZERO = "0" * 40


def needs_lab(paths, project_diff):
    """True if a change to `paths` can change the Lab build. `project_diff` is the zero-context patch of project.yml."""
    if any(path.startswith(LAB_PATHS) or path in LAB_FILES for path in paths):
        return True
    return gate.VERSION_FILE in paths and not gate.version_only(project_diff)


def diff_between(base, head, cwd=None):
    paths = gate.parse_paths(gate.git("diff", "--name-only", "--no-renames", base, head, cwd=cwd))
    patch = gate.git(
        "diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", base, head, "--", gate.VERSION_FILE, cwd=cwd
    )
    return paths, patch


def plan(base, head, cwd=None):
    """'true' or 'false'. A missing base (new branch, forced push) or a failed git call runs the build."""
    if not base or base == ZERO:
        return "true"
    try:
        return "true" if needs_lab(*diff_between(base, head, cwd)) else "false"
    except Exception:  # noqa: BLE001 - any doubt builds
        return "true"


def covering(commits, green, changed, version_diff):
    """Like green_test_gate.covering, for Lab. `commits` are newest first."""
    for sha in commits:
        if green(sha):
            return sha, None
        if needs_lab(changed(sha), version_diff(sha)):
            return None, f"no green Lab run for {sha}, and it changes files that Lab covers"
    return None, f"no green Lab run in the last {len(commits)} commits"


def green_on(repo, commit, read=gate.api):
    runs = read(f"repos/{repo}/actions/workflows/lab.yml/runs?head_sha={commit}&status=success&per_page=100")
    return any(
        gate.proves(run, read(f"repos/{repo}/actions/runs/{run['id']}/jobs?per_page=100")["jobs"], REQUIRED_JOBS)
        for run in runs["workflow_runs"]
    )


def main(args):
    if args[0] == "plan":
        line = f"run={plan(args[1], args[2])}"
        print(line)
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                output.write(line + "\n")
        return 0
    repo = os.environ["GITHUB_REPOSITORY"]
    try:
        found, reason = covering(
            gate.commits_from(args[-1]),
            lambda sha: green_on(repo, sha),
            gate.changed,
            gate.version_diff,
        )
    except Exception as error:  # noqa: BLE001 - a run or history that cannot be read blocks
        found, reason = None, f"cannot read the Lab runs: {error}"
    print(found or reason)
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
