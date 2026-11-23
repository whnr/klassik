"""Sets the "What to Test" text of a TestFlight build from docs/what-to-test.md.

Usage: testflight_notes.py --check            validates version, length, style, and staleness
       testflight_notes.py --release-summary  prints the text for the Summary of the GitHub release
       testflight_notes.py <build-number>     waits for the build, then sets the text
Env for the second form: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8.
The file starts with the line "Klassik X.Y.Z". Apple allows 4000 characters.
"""

import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# This backstop detects development terms; the release review checks app meaning.
DEVELOPMENT_TERMS = re.compile(
    r"\b(?:CI|workflows?|GitHub|tokens?|secrets?|AGENTS\.md|README|"
    r"repositories|repository|repos?|branches|branch|pull\s+requests?|Xcode)\b",
    re.IGNORECASE,
)

BEAD_ID = re.compile(r"\bsz-[a-z0-9]")
NUMBERED_CHECK = re.compile(r"^\s*\d+[.)]\s", re.MULTILINE)
# The text is a feature summary: about 100 words. The cap leaves room and still stops a checklist.
MAX_WORDS = 150


def validate(notes, version, previous=None):
    if not notes.startswith(f"Klassik {version}\n"):
        raise ValueError(
            f"docs/what-to-test.md must start with the line 'Klassik {version}'. Write the notes for this release."
        )
    if len(notes) > 4000:
        raise ValueError(f"docs/what-to-test.md has {len(notes)} characters; TestFlight allows 4000.")
    if BEAD_ID.search(notes):
        raise ValueError("docs/what-to-test.md names a bead ID. Testers cannot read the ledger.")
    match = DEVELOPMENT_TERMS.search(notes)
    if match:
        raise ValueError(f"Development term in docs/what-to-test.md: {match.group()}. Use installed-app checks only.")
    body = notes.split("\n", 1)[1]
    words = len(body.split())
    if words > MAX_WORDS:
        raise ValueError(f"docs/what-to-test.md has {words} words; the feature summary allows {MAX_WORDS}. Write one short bullet per change.")
    if NUMBERED_CHECK.search(body):
        raise ValueError("docs/what-to-test.md has numbered checks. Write one bullet per feature change, not a regression checklist.")
    if previous:
        old = {line.strip() for line in previous.splitlines()[1:] if line.strip()}
        repeated = [line.strip() for line in body.splitlines() if line.strip() in old]
        if repeated:
            raise ValueError(f"docs/what-to-test.md repeats a line of the last release's notes: {repeated[0]!r}. Write this release's changes.")
    return notes


def previous_notes(root, version):
    """The notes of the newest release tag, or None when this version is already tagged or git has no tags."""
    git = ["git", "-C", str(root)]
    tag = subprocess.run(git + ["tag", "--list", "v*", "--sort=-v:refname"], capture_output=True, text=True)
    newest = tag.stdout.split()[0] if tag.stdout.split() else None
    if tag.returncode or not newest or newest == f"v{version}":
        return None
    old = subprocess.run(git + ["show", f"{newest}:docs/what-to-test.md"], capture_output=True, text=True)
    return old.stdout if old.returncode == 0 else None


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    notes = (root / "docs/what-to-test.md").read_text().strip()
    version = re.search(r'^ *MARKETING_VERSION: "(.*)"', (root / "project.yml").read_text(), re.M).group(1)
    try:
        validate(notes, version, previous_notes(root, version))
    except ValueError as error:
        sys.exit(str(error))
    if sys.argv[1:] == ["--check"]:
        return
    if sys.argv[1:] == ["--release-summary"]:
        print("## Summary\n\n" + notes.split("\n", 1)[1].strip())
        return

    import jwt  # pyjwt[crypto]

    API = "https://api.appstoreconnect.apple.com"

    def call(method, path, body=None, **params):
        now = int(time.time())
        token = jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
            os.environ["ASC_KEY_P8"],
            algorithm="ES256",
            headers={"kid": os.environ["ASC_KEY_ID"]},
        )
        query = f"?{urllib.parse.urlencode(params)}" if params else ""
        request = urllib.request.Request(
            f"{API}{path}{query}",
            method=method,
            data=json.dumps(body).encode() if body else None,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            sys.exit(f"App Store Connect answered HTTP {error.code} for {method} {path}: {error.read().decode()[:400]}")

    build_number = sys.argv[1]
    app = call("GET", "/v1/apps", **{"filter[bundleId]": "de.whnr.klassik"})["data"][0]["id"]
    # A build shows up in the API a few minutes after altool finishes, and is usable once processing ends.
    build = None
    for _ in range(60):
        found = call("GET", "/v1/builds", **{"filter[app]": app, "filter[version]": build_number, "limit": 1})["data"]
        if found and found[0]["attributes"]["processingState"] == "VALID":
            build = found[0]["id"]
            break
        time.sleep(30)
    if not build:
        sys.exit(f"Build {build_number} was not ready after 30 minutes.")

    existing = call("GET", f"/v1/builds/{build}/betaBuildLocalizations")["data"]
    current = next((item for item in existing if item["attributes"]["locale"] == "en-US"), None)
    if current:
        call(
            "PATCH",
            f"/v1/betaBuildLocalizations/{current['id']}",
            {"data": {"type": "betaBuildLocalizations", "id": current["id"], "attributes": {"whatsNew": notes}}},
        )
    else:
        call(
            "POST",
            "/v1/betaBuildLocalizations",
            {
                "data": {
                    "type": "betaBuildLocalizations",
                    "attributes": {"locale": "en-US", "whatsNew": notes},
                    "relationships": {"build": {"data": {"type": "builds", "id": build}}},
                }
            },
        )
    print(f"What to Test set for build {build_number} ({version}).")


if __name__ == "__main__":
    main()
