"""Creates the GitHub release of a version tag.

Usage: github_release.py <tag>           creates the release; does nothing when it exists
       github_release.py --body <tag>    prints the release body only
Env: GH_TOKEN, GITHUB_REPOSITORY (owner/name).

The body is the Summary of scripts/testflight_notes.py --release-summary, then the Changes of the PRs merged
since the previous v* tag, grouped as Keep a Changelog groups. Any failure exits non-zero, so the workflow job fails.
A PR label `added`, `changed`, `fixed` or `removed` picks the group; without one the first word of the title does.
"""

import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GROUPS = ("Added", "Changed", "Fixed", "Removed")
FIRST_WORDS = {
    "Added": {"add", "adds", "introduce"},
    "Fixed": {"fix", "fixes", "repair", "undo", "restore", "correct", "keep"},
    "Removed": {"remove", "removes", "delete", "drop", "retire"},
}
MERGE_SUBJECT = re.compile(r"^Merge pull request #(\d+) from ")
SQUASH_SUBJECT = re.compile(r"\(#(\d+)\)$")
BEAD_PREFIX = re.compile(r"^\[sz-[a-z0-9.]+\]\s*")
RELEASE_TITLE = re.compile(r"^(?:\[[^\]]*\]\s*)?Release Klassik\b")
TAG = re.compile(r"^v\d+\.\d+\.\d+$")


def version_key(tag):
    return tuple(int(part) for part in tag[1:].split("."))


def previous_tag(tags, tag):
    """The newest v* tag below `tag`, or None for the first release."""
    if not TAG.match(tag):
        raise ValueError(f"{tag!r} is not a release tag vX.Y.Z.")
    older = [t for t in tags if TAG.match(t) and version_key(t) < version_key(tag)]
    return max(older, key=version_key) if older else None


def pr_number(subject):
    match = MERGE_SUBJECT.match(subject) or SQUASH_SUBJECT.search(subject)
    return int(match.group(1)) if match else None


def group_of(title, labels):
    for label in labels:
        if label.capitalize() in GROUPS:
            return label.capitalize()
    words = title.split()
    first = words[0].lower() if words else ""
    for group, names in FIRST_WORDS.items():
        if first in names:
            return group
    return "Changed"


def render_changes(entries):
    """`entries` are (group, text, link) tuples in merge order. Empty groups are left out."""
    if not entries:
        raise ValueError("No change since the previous tag. A release with an empty Changes section is a mistake.")
    parts = ["## Changes"]
    for group in GROUPS:
        lines = [f"- {text}: {link}" for g, text, link in entries if g == group]
        if lines:
            parts.append(f"### {group}\n" + "\n".join(lines))
    return "\n\n".join(parts)


def build_body(summary, changes):
    if not summary.startswith("## Summary\n") or not summary.partition("\n")[2].strip():
        raise ValueError("The release Summary is empty or has no '## Summary' heading.")
    return f"{summary.strip()}\n\n{changes}\n"


def run(*command):
    done = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
    if done.returncode:
        raise RuntimeError(f"{' '.join(command[:3])} failed: {done.stderr.strip() or done.stdout.strip()}")
    return done.stdout


def gh_json(*args):
    return json.loads(run("gh", *args))


def collect(tag, repo):
    tags = run("git", "tag", "--list", "v*").split()
    if tag not in tags:
        raise ValueError(f"Tag {tag} does not exist in this checkout. Fetch tags.")
    previous = previous_tag(tags, tag)
    span = f"{previous}..{tag}" if previous else tag
    log = run("git", "log", "--first-parent", "--format=%H%x09%s", span).splitlines()
    entries = []
    for line in reversed(log):
        sha, _, subject = line.partition("\t")
        number = pr_number(subject)
        if number is None:
            entries.append(
                ("Changed", BEAD_PREFIX.sub("", subject), f"[{sha[:7]}](https://github.com/{repo}/commit/{sha})")
            )
            continue
        pr = gh_json("pr", "view", str(number), "--repo", repo, "--json", "title,labels")
        title = BEAD_PREFIX.sub("", pr["title"])
        if RELEASE_TITLE.match(title):
            continue
        labels = [label["name"] for label in pr["labels"]]
        entries.append((group_of(title, labels), title, f"[#{number}](https://github.com/{repo}/pull/{number})"))
    return render_changes(entries)


def body_for(tag, repo):
    summary = run(sys.executable, "scripts/testflight_notes.py", "--release-summary")
    return build_body(summary, collect(tag, repo))


def create(tag, repo):
    exists = subprocess.run(["gh", "release", "view", tag, "--repo", repo], capture_output=True, text=True, cwd=ROOT)
    if exists.returncode == 0:
        print(f"Release {tag} exists; left unchanged.")
        return
    if "release not found" not in exists.stderr:
        raise RuntimeError(f"Cannot tell if release {tag} exists: {exists.stderr.strip()}")
    body = body_for(tag, repo)
    run(
        "gh", "release", "create", tag, "--repo", repo, "--verify-tag", "--latest",
        "--title", f"Klassik {tag[1:]}", "--notes", body,
    )  # fmt: skip
    print(f"Created release {tag}.")


def main(argv):
    repo = os.environ.get("GITHUB_REPOSITORY", "whnr/klassik")
    try:
        if len(argv) == 2 and argv[0] == "--body":
            print(body_for(argv[1], repo))
        elif len(argv) == 1:
            create(argv[0], repo)
        else:
            sys.exit(__doc__)
    except (ValueError, RuntimeError) as error:
        sys.exit(f"::error::GitHub release failed: {error}")


if __name__ == "__main__":
    main(sys.argv[1:])
