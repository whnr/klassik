#!/usr/bin/env python3
"""Checks the decided design: contrast targets of ADR 0034 in every accent and room, and the links between ADRs.

Usage: design/scripts/check.py
Exits 1 on a failed pair or a broken link. Known pairs below target are listed but do not fail.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ACCENTS = ("claret", "green", "plum")
ROOMS = ("light", "lightHighContrast", "dark", "darkHighContrast")
GROUNDS = ("background.page", "background.row", "background.grouped", "background.elevated")
SWIPES = ("swipe.playNext", "swipe.addToQueue", "swipe.download", "swipe.favourite")

# The standard colours are locked (Flo, 2026-11-09). These pairs sit below AA until sz-rs30.1.83.19.17 decides.
KNOWN = {
    ("light", "favourite-off", "background.grouped"),
    ("dark", "favourite-off", "background.row"),
    ("dark", "favourite-off", "background.elevated"),
}


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
    """The pairs that ADR 0034 promises, as (foreground, background, target)."""
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
    failures, known = [], []
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
                (known if (room, fg, bg) in KNOWN else failures).append(line)
    return failures, known


def check_links():
    broken = []
    for record in sorted((ROOT / "docs/adr").glob("*.md")):
        for target in re.findall(r"\]\(([^)\s]+)\)", record.read_text()):
            if re.match(r"[a-z]+:", target) or target.startswith("#"):
                continue
            if not (record.parent / target.split("#")[0]).exists():
                broken.append(f"{record.name}: {target}")
    return broken


def main():
    failures, known = check_contrast()
    broken = check_links()
    for line in known:
        print(f"known, sz-rs30.1.83.19.17: {line}")
    for line in failures:
        print(f"FAIL contrast: {line}")
    for line in broken:
        print(f"FAIL link: {line}")
    print(f"contrast: {len(failures)} failed, {len(known)} known; links: {len(broken)} broken")
    return 1 if failures or broken else 0


if __name__ == "__main__":
    sys.exit(main())
