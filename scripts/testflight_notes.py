"""Sets the "What to Test" text of a TestFlight build from docs/what-to-test.md.

Usage: testflight_notes.py --check            validates version, bullet format, length, and development terms
       testflight_notes.py <build-number>     waits for the build, then sets the text
Env for the second form: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8.
The file starts with the line "Klassik X.Y.Z", then one "- " bullet per change.
See docs/agents/release-notes.md.
"""

import json
import os
import pathlib
import re
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

BEAD_ID = re.compile(r"\bsz-[a-z0-9]+(?:\.[0-9]+)*\b", re.IGNORECASE)
MAX_BULLET_WORDS = 25
MAX_TOTAL_WORDS = 150


def validate(notes, version):
    if not notes.startswith(f"Klassik {version}\n"):
        raise ValueError(
            f"docs/what-to-test.md must start with the line 'Klassik {version}'. Write the notes for this release."
        )
    bullets = [line for line in notes.splitlines()[1:] if line.strip()]
    if not bullets:
        raise ValueError("docs/what-to-test.md has no bullets. Write one '- ' bullet per change.")
    for line in bullets:
        if not line.startswith("- "):
            raise ValueError(f"Not a bullet in docs/what-to-test.md: {line[:60]!r}. Use one '- ' line per change.")
        words = len(line[2:].split())
        if words > MAX_BULLET_WORDS:
            raise ValueError(f"A bullet has {words} words; the limit is {MAX_BULLET_WORDS}: {line[:60]!r}.")
    total = sum(len(line[2:].split()) for line in bullets)
    if total > MAX_TOTAL_WORDS:
        raise ValueError(f"docs/what-to-test.md has {total} words; the limit is {MAX_TOTAL_WORDS}.")
    if BEAD_ID.search(notes):
        raise ValueError("A bead id in docs/what-to-test.md. Testers see a feature summary only.")
    match = DEVELOPMENT_TERMS.search(notes)
    if match:
        raise ValueError(f"Development term in docs/what-to-test.md: {match.group()}. Use installed-app checks only.")
    return notes


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    notes = (root / "docs/what-to-test.md").read_text().strip()
    version = re.search(r'^ *MARKETING_VERSION: "(.*)"', (root / "project.yml").read_text(), re.M).group(1)
    try:
        validate(notes, version)
    except ValueError as error:
        sys.exit(str(error))
    if sys.argv[1:] == ["--check"]:
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
