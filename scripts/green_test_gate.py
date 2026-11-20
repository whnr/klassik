"""Finds the green Test run that covers a commit, for the TestFlight gate.

A push to main that changes only ignored paths starts no Test run (the paths-ignore list of test.yml).
Such a commit is covered by the newest ancestor with a green run, if every change since then is ignored.
The ignore list here must match `pull_request.paths-ignore` and `push.paths-ignore` in test.yml.

Usage: GH_TOKEN=... GITHUB_REPOSITORY=owner/repo python3 scripts/green_test_gate.py <sha>
Prints the covering SHA. Exits 1 and prints the reason when none covers the commit.
"""

import json
import os
import subprocess
import sys

IGNORED = ["**.md", "LICENSE", "docs/**"]
DEPTH = 50  # Docs-only pushes in a row are few; a longer chain needs a real Test run.


def is_ignored(path):
    """GitHub's `**` crosses directories and `*` does not; fnmatch's `*` crosses both, so a prefix test stands in."""
    return any(
        path.endswith(pattern[2:])
        if pattern.startswith("**")
        else path.startswith(pattern[:-2])
        if pattern.endswith("/**")
        else path == pattern
        for pattern in IGNORED
    )


def covering(commits, changed, green):
    """The first of `commits` (newest first) with a green run, if each commit before it changed only ignored paths.

    `changed(sha)` gives the paths that the commit changed, `green(sha)` tells if Test passed on it.
    Returns (sha, None), or (None, reason).
    """
    for sha in commits:
        if green(sha):
            return sha, None
        if not all(is_ignored(path) for path in changed(sha)):
            return None, f"no green Test run for {sha}, and it changes files that Test covers"
    return None, f"no green Test run in the last {len(commits)} commits"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def main(sha):
    repo = os.environ["GITHUB_REPOSITORY"]

    def green(commit):
        query = f"repos/{repo}/actions/workflows/test.yml/runs?head_sha={commit}&status=success"
        out = subprocess.run(["gh", "api", query], capture_output=True, text=True, check=True).stdout
        return json.loads(out)["total_count"] > 0

    def changed(commit):
        return git("diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", commit).split("\n")

    commits = git("rev-list", "--first-parent", f"--max-count={DEPTH}", sha).split()
    found, reason = covering(commits, changed, green)
    if found is None:
        print(reason)
        sys.exit(1)
    print(found)


if __name__ == "__main__":
    main(sys.argv[1])
