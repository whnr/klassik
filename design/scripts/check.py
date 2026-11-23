#!/usr/bin/env python3
"""Checks the decided design: the contrast targets in every accent and room, and the links between ADRs.

The colour rules are on the token page of the specimen.

A record that replaces part of another must be answered: the old record links back, and its index row names it.

Usage: design/scripts/check.py
Exits 1 on a failed pair or a broken link.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ACCENTS = ("claret", "green", "plum")
ROOMS = ("light", "lightHighContrast", "dark", "darkHighContrast")
GROUNDS = ("background.page", "background.row", "background.grouped", "background.elevated")
SWIPES = ("swipe.playNext", "swipe.addToQueue", "swipe.download", "swipe.favourite")


def luminance(hex_colour):
    channels = [int(hex_colour[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def ratio(a, b):
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def colours(group, path=()):
    """Flattens a palette room to {"text.primary": "#281F20", ...}. Translucent fills have no plain hex and stay out."""
    out = {}
    for key, value in group.items():
        if key.startswith("$") or not isinstance(value, dict):
            continue
        if "$value" in value:
            hex_colour = value["$value"].get("hex") if isinstance(value["$value"], dict) else None
            if hex_colour and len(hex_colour) == 7 and value["$value"].get("alpha", 1) == 1:
                out[".".join(path + (key,))] = hex_colour
        else:
            out.update(colours(value, path + (key,)))
    return out


def pairs(room):
    """The pairs that the token page of the specimen promises, as (foreground, background, target)."""
    if room.endswith("HighContrast"):
        # Increase Contrast: AAA for text, 4.5:1 for marks, on every ground.
        text, mark, label = 7, 4.5, 7
        out = [(t, g, text) for t in ("text.primary", "text.secondary", "tint") for g in GROUNDS]
        out += [(m, g, mark) for m in ("favourite", "favourite-off", "timeline.played") for g in GROUNDS]
    else:
        # Standard modes: WCAG 2.2 AA. Text 4.5:1 and marks 3:1 on every ground.
        text, mark, label = 4.5, 3, 4.5
        out = [(t, g, text) for t in ("text.primary", "text.secondary", "tint") for g in GROUNDS]
        out += [(m, g, mark) for m in ("favourite", "favourite-off", "timeline.played") for g in GROUNDS]
    out += [("on-accent", "accent.fill", label), ("timeline.played", "timeline.unplayed", mark)]
    out += [("#FFFFFF", s, label) for s in SWIPES]
    return out


def check_contrast():
    failures = []
    for accent in ACCENTS:
        palette = json.loads((ROOT / f"design/accent-{accent}.tokens.json").read_text())["palette"]
        for room in ROOMS:
            values = colours(palette[room])
            for fg, bg, target in pairs(room):
                a = fg if fg.startswith("#") else values[fg]
                r = ratio(a, values[bg])
                if r + 0.005 >= target:
                    continue
                line = f"{accent} {room}: {fg} on {bg} {r:.2f}:1, target {target}:1"
                failures.append(line)
    return failures


def check_links():
    broken = []
    for record in sorted((ROOT / "docs/adr").glob("*.md")):
        for target in re.findall(r"\]\(([^)\s]+)\)", record.read_text()):
            if re.match(r"[a-z]+:", target) or target.startswith("#"):
                continue
            if not (record.parent / target.split("#")[0]).exists():
                broken.append(f"{record.name}: {target}")
    return broken


ADR_LIST = re.compile(
    r"\b(?:ADRs?|records?)\s+((?:0\d{3}|(?<=ADR )\d{1,4}|(?<=ADRs )\d{1,4})"
    r"(?:(?:,\s*|\s+and\s+|\s+or\s+|,\s*and\s+)\d{1,4})*)",
    re.I,
)
ADR_FILE = re.compile(r"\b(0\d{3})-[a-z]+(?:-[a-z]+)*\b")
ADR_DASH = re.compile(r"\bADR-(\d{1,4})\b", re.I)
ADR_CUE = re.compile(
    r"\b(?:see|as in|per|by|keeps?)\s+(00\d\d)\b",
    re.I,
)
BARE = re.compile(r"\b(0\d{3})\b")
LINK = re.compile(r"\[[^\]]*\]\([^)]*\)")


def mentioned(text, in_adr):
    """The ADR numbers that `text` names. Only an ADR context counts, so years and build numbers stay out.

    Context: a number after "ADR", "ADRs" or "records", an ADR file name or "ADR-" prefix,
    or a number after a cue word such as "see".
    Inside docs/adr every four-digit number with a leading zero counts. Links are checked by check_links.
    """
    found = set()
    for match in ADR_LIST.finditer(text):
        found.update(n.zfill(4) for n in re.findall(r"\d+", match.group(1)))
    found.update(ADR_FILE.findall(text))
    found.update(n.zfill(4) for n in ADR_DASH.findall(text))
    found.update(ADR_CUE.findall(text))
    if in_adr:
        body = "\n".join(line for line in text.splitlines() if not re.match(r"#\s+0\d{3}\.", line))
        found.update(BARE.findall(LINK.sub("", body)))
    return found


def check_mentions(root=ROOT):
    """No file names an ADR number that has no record in docs/adr. A tracked file that cannot be read fails."""
    have = {record.name[:4] for record in (root / "docs/adr").glob("0*.md")}
    if not have:
        return ["docs/adr: no ADR records found"]
    files = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout.split("\n")
    problems = []
    for name in filter(None, files):
        try:
            data = (root / name).read_bytes()
        except OSError as error:
            problems.append(f"{name}: cannot be read ({error.strerror or error})")
            continue
        try:
            text = data.decode()
        except UnicodeDecodeError:
            continue
        in_adr = name.startswith("docs/adr/") and name.endswith(".md") and name != "docs/adr/README.md"
        for n in mentioned(text, in_adr):
            if n not in have:
                problems.append(f"{name}: ADR {n} does not exist")
    return sorted(set(problems))


VAGUE = re.compile(
    r"\b(?:earlier|former|previous|prior|deleted|retired|removed)\s+(?:ADRs?|decision records?|records?)\b"
    r"|\b(?:the|an?|existing)\s+ADRs?\s+(?:on|about|records?|says?|requires?|states?|sets?)\b",
    re.I,
)
VAGUE_SKIP = ("docs/adr/README.md", "design/scripts/check.py", "scripts/test_design_check.py")


def check_vague(root=ROOT):
    """No file points to an ADR without naming it. State the rule, or link the record that holds it."""
    files = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout.split("\n")
    problems = []
    for name in filter(None, files):
        if name in VAGUE_SKIP or name.endswith((".json", ".png", ".jpg", ".ttf", ".otf")):
            continue
        try:
            text = (root / name).read_text()
        except (OSError, UnicodeDecodeError):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if VAGUE.search(line):
                problems.append(f"{name}:{number}: points to an ADR without naming it")
    return problems


# A specimen file named in parentheses, such as "(design/specimen/tokens.html)", and a bead ID in Markdown.
TAG = re.compile(r"\((?:design/specimen/)?[a-z-]{3,}\.html(?:, [^)]*)?\)")
BEAD = re.compile(r"\bsz-(?=[a-z0-9.]*\d)[a-z0-9.]+")
TAG_SKIP = ("design/scripts/check.py", "scripts/test_design_check.py")


def check_tags(root=ROOT):
    """Comments name no specimen file in parentheses, and documents name no bead."""
    files = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout.split("\n")
    problems = []
    for name in filter(None, files):
        if name in TAG_SKIP or name.endswith((".png", ".jpg", ".ttf", ".otf", ".json")):
            continue
        try:
            text = (root / name).read_text()
        except (OSError, UnicodeDecodeError):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if TAG.search(line) and not name.endswith(".md"):
                problems.append(f"{name}:{number}: a comment tags a specimen file")
            if name.endswith(".md") and BEAD.search(line):
                problems.append(f"{name}:{number}: a document names a bead")
    return problems


def check_chain():
    """The rule of docs/adr/README.md: each "Replaces" sentence in a header line has a pointer back and an index row."""
    adr = ROOT / "docs/adr"
    index = (adr / "README.md").read_text()
    missing = []
    for record in sorted(adr.glob("0*.md")):
        header = record.read_text().splitlines()[2]
        for sentence in re.split(r"(?<=\.) ", header):
            if not sentence.startswith("Replaces"):
                continue
            for target in re.findall(r"\]\((0\d{3}-[^)]+\.md)\)", sentence):
                if f"({record.name})" not in (adr / target).read_text().splitlines()[2]:
                    missing.append(f"{target}: no pointer back to {record.name}")
                row = next((line for line in index.splitlines() if line.startswith(f"| [{target[:4]}]")), "")
                if not re.search(rf"replaced by [^)]*\b{record.name[:4]}\b", row):
                    missing.append(f"README.md: the row of {target} does not name {record.name[:4]}")
    return missing


def main():
    failures = check_contrast()
    broken = check_links() + check_chain() + check_mentions() + check_vague() + check_tags()
    for line in failures:
        print(f"FAIL contrast: {line}")
    for line in broken:
        print(f"FAIL link: {line}")
    print(f"contrast: {len(failures)} failed; links: {len(broken)} broken")
    return 1 if failures or broken else 0


if __name__ == "__main__":
    sys.exit(main())
