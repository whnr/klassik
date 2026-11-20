"""Finds the green Test run that covers a commit, for the TestFlight gate.

A push to main that changes only ignored paths starts no Test run (the paths-ignore list of test.yml).
A release commit changes only the version lines of project.yml and the TestFlight notes. Its Test run
would build the same code as its parent, so the release need not wait for it.
Such a commit is covered by the newest ancestor with a green run, if every change since then is
ignored or a version line. Any other change fails closed.
The ignore list here must match `pull_request.paths-ignore` and `push.paths-ignore` in test.yml.

Usage: GH_TOKEN=... GITHUB_REPOSITORY=owner/repo python3 scripts/green_test_gate.py <sha>
Prints the covering SHA. Exits 1 and prints the reason when none covers the commit.
"""

import json
import os
import re
import subprocess
import sys

IGNORED = ["**.md", "LICENSE", "docs/**"]
DEPTH = 50  # Docs-only pushes in a row are few; a longer chain needs a real Test run.
VERSION_FILE = "project.yml"
# CURRENT_PROJECT_VERSION is replaced by the TestFlight run number at archive time.
VERSION_LINE = re.compile(r'[+-] *(MARKETING_VERSION|CURRENT_PROJECT_VERSION): "?[0-9]+(\.[0-9]+)*"?')
# The headers of a plain content change. A rename, mode change, deletion or binary diff adds other lines.
DIFF_HEADERS = ("diff --git ", "index ", "--- ", "+++ ")


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


def version_only(diff):
    """True if `diff` (zero-context patch of project.yml) changes at least one line and only version lines."""
    lines = diff.splitlines()
    hunks = next((i for i, line in enumerate(lines) if line.startswith("@@")), len(lines))
    if not all(line.startswith(DIFF_HEADERS) for line in lines[:hunks]):
        return False
    body = [line for line in lines[hunks:] if not line.startswith("@@")]
    return bool(body) and all(VERSION_LINE.fullmatch(line.rstrip()) for line in body)


def covering(commits, changed, green, version_diff):
    """The first of `commits` (newest first) with a green run, if each commit before it changed only ignored
    paths and version lines.

    `changed(sha)` gives the paths that the commit changed, `green(sha)` tells if Test passed on it, and
    `version_diff(sha)` gives the commit's patch of project.yml.
    Returns (sha, None), or (None, reason).
    """
    for sha in commits:
        if green(sha):
            return sha, None
        covered = [path for path in changed(sha) if not is_ignored(path)]
        if covered == [VERSION_FILE] and version_only(version_diff(sha)):
            continue
        if covered:
            return None, f"no green Test run for {sha}, and it changes files that Test covers: {', '.join(covered)}"
    return None, f"no green Test run in the last {len(commits)} commits"


def run(*argv, cwd=None):
    # stderr stays on the job log: it names the real cause when git or gh fails.
    return subprocess.run(argv, stdout=subprocess.PIPE, text=True, check=True, cwd=cwd).stdout


def git(*args, cwd=None):
    return run("git", *args, cwd=cwd)


def parse_paths(output):
    """The changed paths in `git diff-tree --name-only` output. The output ends with a newline."""
    return [path for path in output.splitlines() if path]


def changed(commit, cwd=None):
    return parse_paths(git("diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", commit, cwd=cwd))


def version_diff(commit, cwd=None):
    """The patch of project.yml against the first parent. A root commit gives an empty patch, which fails closed."""
    options = ["-p", "-U0", "--no-color", "--no-ext-diff", "--no-renames", "--no-commit-id", "-m", "--first-parent"]
    return git("diff-tree", *options, commit, "--", VERSION_FILE, cwd=cwd)


def commits_from(sha, cwd=None):
    return git("rev-list", "--first-parent", f"--max-count={DEPTH}", sha, cwd=cwd).split()


def main(sha):
    repo = os.environ["GITHUB_REPOSITORY"]

    def green(commit):
        query = f"repos/{repo}/actions/workflows/test.yml/runs?head_sha={commit}&status=success"
        out = run("gh", "api", query)
        return json.loads(out)["total_count"] > 0

    found, reason = covering(commits_from(sha), changed, green, version_diff)
    if found is None:
        print(reason)
        sys.exit(1)
    print(found)


if __name__ == "__main__":
    main(sys.argv[1])
