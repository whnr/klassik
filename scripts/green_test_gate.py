"""Finds the green Test run that covers a commit, for the TestFlight gate.

A push to main that changes only ignored paths (documentation, the Playback Lab) starts no Test run
(the paths-ignore list of test.yml).
A release commit changes only the version lines of project.yml and the TestFlight notes. Its Test run
would build the same code as its parent, so the release need not wait for it.
Such a commit is covered by the newest ancestor with a green run, if every change since then is
ignored or a version line. Any other change fails closed.
A merge commit that adds nothing to the PR head it merges is covered by the green run of that head
(see merged_head). Its own run on main skips the build.
A main push runs no Release launch check, and a pull request run opens it only for a release title. So a commit
is covered only by a run that passed the Release launch check: its own run, or, for a merge, the green PR head
run or the run of the merge commit itself (see `launched`). A plain merge still skips its build, because
`merged` needs only build and unit tests on the head.
The ignore list here must match `pull_request.paths-ignore` and `push.paths-ignore` in test.yml.

Usage: GH_TOKEN=... GITHUB_REPOSITORY=owner/repo python3 scripts/green_test_gate.py [merged] <sha>
Prints the covering SHA. Exits 1 and prints the reason when none covers the commit, or when a run
cannot be read. With `merged`, only the green PR head of a merge commit covers it. That mode is the plan of
a main run, which runs no Release launch, so it does not ask for it.
"""

import json
import os
import re
import subprocess
import sys

# The Playback Lab and its workflows are apart from the Klassik build, so changes to only those paths need no Test run.
IGNORED = [
    "**.md",
    "LICENSE",
    "docs/**",
    "KlassikLab/**",
    "KlassikLabTests/**",
    ".github/workflows/lab.yml",
    ".github/workflows/testflight-lab.yml",
]
# A run is green only if these jobs passed. A main run that a PR head covers skips build, so it proves nothing.
REQUIRED_JOBS = ("build", "test")
RELEASE_JOB = "release-launch"
DEPTH = 50  # Docs-only pushes in a row are few; a longer chain needs a real Test run.
VERSION_FILE = "project.yml"
# CURRENT_PROJECT_VERSION is replaced by the TestFlight run number at archive time.
# The value is fully quoted or bare. One quote alone opens a YAML string that takes in the lines after it.
VERSION_LINE = re.compile(
    r'[+-](?P<key> *(?:MARKETING_VERSION|CURRENT_PROJECT_VERSION)): (?:"[0-9]+(?:\.[0-9]+)*"|[0-9]+(?:\.[0-9]+)*)'
)
HUNK = re.compile(r"@@ -(?P<old>[0-9]+)(?:,(?P<removed>[0-9]+))? \+(?P<new>[0-9]+)(?:,(?P<added>[0-9]+))? @@.*")
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
    """True if `diff` (zero-context patch of project.yml) changes at least one line and only replaces version
    values in place.

    A bump never adds or removes a line. So each hunk must remove n lines and add n lines at the same place,
    and the i-th added line must keep the key and indentation of the i-th removed line.
    """
    lines = diff.splitlines()
    hunks = next((i for i, line in enumerate(lines) if line.startswith("@@")), len(lines))
    if hunks == len(lines) or not all(line.startswith(DIFF_HEADERS) for line in lines[:hunks]):
        return False
    rest = lines[hunks:]
    while rest:
        header = HUNK.fullmatch(rest[0])
        if not header:
            return False
        count = int(header["removed"] or 1)
        if count == 0 or header["old"] != header["new"] or int(header["added"] or 1) != count:
            return False
        removed, added, rest = rest[1 : count + 1], rest[count + 1 : 2 * count + 1], rest[2 * count + 1 :]
        if len(added) != count:
            return False
        for old, new in zip(removed, added):
            before, after = VERSION_LINE.fullmatch(old.rstrip()), VERSION_LINE.fullmatch(new.rstrip())
            if not (before and after and old[0] == "-" and new[0] == "+" and before["key"] == after["key"]):
                return False
    return True


def missing_launch(sha, run_sha):
    return (
        f"no green Test run for {sha} with a Release launch: the green run of {run_sha} has no passing Release launch"
    )


def covering(commits, changed, green, version_diff, merged=lambda sha: None, launched=lambda sha, head: False):
    """The first of `commits` (newest first) with a green run, if each commit before it changed only ignored
    paths and version lines. A commit is also covered by the green run of the PR head that `merged(sha)` gives,
    if `launched(sha, head)` says that a Release build opened on the head run or on the run of `sha`.

    `changed(sha)` gives the paths that the commit changed, `green(sha)` tells if Test passed on it, and
    `version_diff(sha)` gives the commit's patch of project.yml. `launched(sha, head)` tells if a Release build
    opened on the run of `head` or of `sha`; a commit that is green needs it on its own run.
    Returns (sha, None), or (None, reason). A reason that follows a green run without a Release launch says so.
    """
    unlaunched = None
    for sha in commits:
        head = merged(sha)
        for run_sha in (sha, head):
            if run_sha and green(run_sha):
                if launched(sha, run_sha):
                    return run_sha, None
                unlaunched = unlaunched or (sha, run_sha)
        covered = [path for path in changed(sha) if not is_ignored(path)]
        if covered == [VERSION_FILE] and version_only(version_diff(sha)):
            continue
        if covered:
            if unlaunched:
                return None, missing_launch(*unlaunched)
            return None, f"no green Test run for {sha}, and it changes files that Test covers: {', '.join(covered)}"
    if unlaunched:
        return None, missing_launch(*unlaunched)
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


def merged_head(commit, cwd=None):
    """The second parent of a merge commit that adds nothing to it, else None.

    The commit has two parents and the tree of the second, and the first parent is in the history of the second.
    A pull_request run tests the PR head merged with main at that time. Main only moves forward, so that main is
    in the history of the first parent, and the run tested this exact tree. Klassik PRs target main.
    A shallow checkout that hides a parent or the history gives None.
    """
    try:
        parents = git("rev-list", "--parents", "--max-count=1", commit, cwd=cwd).split()[1:]
        if len(parents) != 2:
            return None
        first, second = parents
        if git("rev-parse", f"{commit}^{{tree}}", cwd=cwd) != git("rev-parse", f"{second}^{{tree}}", cwd=cwd):
            return None
    except subprocess.CalledProcessError:
        return None
    ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", first, second], cwd=cwd, check=False)
    return second if ancestor.returncode == 0 else None


def proves(workflow_run, jobs, required=REQUIRED_JOBS):
    """True if a Test run of the API passed and its jobs in `required` passed. Missing fields raise."""
    if workflow_run["conclusion"] != "success":
        return False
    results = {job["name"]: job["conclusion"] for job in jobs}
    return all(results.get(name) == "success" for name in required)


def api(query):
    return json.loads(run("gh", "api", query))


def green_on(repo, commit, read=api, required=REQUIRED_JOBS):
    runs = read(f"repos/{repo}/actions/workflows/test.yml/runs?head_sha={commit}&status=success&per_page=100")
    return any(
        proves(
            workflow_run,
            read(f"repos/{repo}/actions/runs/{workflow_run['id']}/jobs?per_page=100")["jobs"],
            required,
        )
        for workflow_run in runs["workflow_runs"]
    )


def main(args, read=api):
    repo = os.environ["GITHUB_REPOSITORY"]
    only_merged = args[0] == "merged"
    sha = args[-1]

    def green(commit):
        return green_on(repo, commit, read)

    def launched(commit, head):
        # A main push no longer runs the Release launch check, so the proof is a release PR head run, or a
        # manual or nightly run of the commit itself. A PR head run opens it only for a release title, which can
        # come after its last push.
        with_release = REQUIRED_JOBS + (RELEASE_JOB,)
        return green_on(repo, head, read, with_release) or green_on(repo, commit, read, (RELEASE_JOB,))

    try:
        if only_merged:
            head = merged_head(sha)
            found, reason = (head, None) if head and green(head) else (None, f"{sha} is no merge of a green PR head")
        else:
            found, reason = covering(commits_from(sha), changed, green, version_diff, merged_head, launched)
    except (subprocess.CalledProcessError, LookupError, TypeError, ValueError) as error:
        found, reason = None, f"cannot read the history or the Test runs: {error!r}"
    if found is None:
        print(reason)
        sys.exit(1)
    print(found)


if __name__ == "__main__":
    main(sys.argv[1:])
