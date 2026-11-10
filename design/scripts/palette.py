#!/usr/bin/env python3
"""Solves Klassik's colours from their contrast targets and writes design/accent-*.tokens.json (ADR 0034, ADR 0037).

Usage: design/scripts/palette.py [--check]
--check writes nothing and fails when a palette file is not current.

Each colour starts in OKLCH. Its lightness comes from its WCAG target on the ground it sits on; chroma then drops
at fixed lightness and hue until the colour fits sRGB. The constants below are the decision; the files are output.
"""

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / "design"

# ---------- the decision ----------
# h: accent hue. Day text is a deep jewel; night text is its lighter, quieter twin.
FAMILIES = {
    "claret": dict(label="Claret", h=6, dayC=0.13, nightC=0.11, fillL=0.38, fillC=0.12),
    "green": dict(label="Bottle green", h=160, dayC=0.09, nightC=0.09, fillL=0.40, fillC=0.08),
    "plum": dict(label="Plum", h=345, dayC=0.11, nightC=0.10, fillL=0.38, fillC=0.10),
}
# The paper: middle (#faf3e5), never white. The hall: a warm near-black tinted toward the accent, never black.
PAPER_L, PAPER_C, PAPER_H = 0.966, 0.020, 85
HALL_L, HALL_C = 0.18, 0.010
# Swipe actions: one hue per action, white labels. Favourite takes the accent hue. Add to Queue and Favourite sit
# OKLab L 0.12 darker, so the pair on each edge still differs for colour-blind eyes.
SWIPES = {"playNext": (285, 0.10), "addToQueue": (60, 0.10), "download": (215, 0.10), "favourite": (None, 0.19)}
SWIPE_DARKER = {"addToQueue", "favourite"}
SWIPE_STEP = 0.12
# Increase Contrast holds AAA on every ground, not only the page: text 7:1, marks 4.5:1.
HC_TEXT_FLOOR, HC_MARK_FLOOR = 7, 4.5
# The dark timeline: the unplayed part is a mix of text into the page, about 2:1 (ADR 0035).
DARK_UNPLAYED_MIX = {False: 0.32, True: 0.30}
GROUNDS = ("background-page", "background-row", "background-grouped", "background-elevated")


# ---------- colour maths (Ottosson OKLab, WCAG 2) ----------
def oklab_to_linear(L, a, b):
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    # The LMS cone responses.
    cl, cm, cs = l_**3, m_**3, s_**3
    return (
        4.0767416621 * cl - 3.3077115913 * cm + 0.2309699292 * cs,
        -1.2684380046 * cl + 2.6097574011 * cm - 0.3413193965 * cs,
        -0.0041960863 * cl - 0.7034186147 * cm + 1.7076147010 * cs,
    )


def oklch_to_linear(L, C, h):
    return oklab_to_linear(L, C * math.cos(math.radians(h)), C * math.sin(math.radians(h)))


def in_gamut(linear):
    return all(-1e-4 <= c <= 1 + 1e-4 for c in linear)


def encode(c):
    c = min(max(c, 0.0), 1.0)
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def decode(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexof(L, C, h):
    """OKLCH to sRGB hex. Chroma drops until the colour fits sRGB."""
    while C > 0 and not in_gamut(oklch_to_linear(L, C, h)):
        C -= 0.001
    r, g, b = (round(encode(c) * 255) for c in oklch_to_linear(L, max(C, 0), h))
    return f"#{r:02x}{g:02x}{b:02x}"


def channels(hx):
    return [int(hx[i : i + 2], 16) / 255 for i in (1, 3, 5)]


def oklab(hx):
    r, g, b = (decode(c) for c in channels(hx))
    cl = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    cm = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    cs = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (
        0.2104542553 * cl + 0.7936177850 * cm - 0.0040720468 * cs,
        1.9779984951 * cl - 2.4285922050 * cm + 0.4505937099 * cs,
        0.0259040371 * cl + 0.7827717662 * cm - 0.8086757660 * cs,
    )


def oklch(hx):
    L, a, b = oklab(hx)
    return L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360


def luminance(hx):
    r, g, b = (decode(c) for c in channels(hx))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def wcag(a, b):
    x, y = sorted([luminance(a), luminance(b)])
    return (y + 0.05) / (x + 0.05)


def solve(C, h, ground, target, darker, step=0.0):
    """The lightness nearest the ground that still reaches the target ratio, then a step darker."""
    lo, hi = 0.0, 1.0
    for _ in range(40):
        mid = (lo + hi) / 2
        ok = wcag(hexof(mid, C, h), ground) >= target
        if darker:
            lo, hi = (mid, hi) if ok else (lo, mid)
        else:
            lo, hi = (lo, mid) if ok else (mid, hi)
    return hexof((lo if darker else hi) - step, C, h)


def solve_on(C, h, values, target, floor, darker):
    """Reach the target on the page and the floor on every other ground: the weakest ground decides."""
    found = [solve(C, h, values["background-page"], target, darker)]
    found += [solve(C, h, values[k], floor, darker) for k in GROUNDS[1:] if floor]
    return (min if darker else max)(found, key=luminance)


def mix(a, b, f):
    """An OKLab mix: f of b into a."""
    la, lb = oklab(a), oklab(b)
    L, x, y = (la[i] + (lb[i] - la[i]) * f for i in range(3))
    return hexof(L, math.hypot(x, y), math.degrees(math.atan2(y, x)))


# ---------- the rooms ----------
def light(fam, high):
    C = PAPER_C * (0.6 if high else 1)
    page = hexof(PAPER_L, C, PAPER_H)
    nh = fam["h"]
    out = {
        "background-page": page,
        "background-row": page,
        "background-grouped": hexof(PAPER_L - 0.03, C * 1.2, PAPER_H),
        "background-elevated": hexof(min(PAPER_L + 0.012, 0.99), C * 0.7, PAPER_H),
        "text-primary": hexof(0.18 if high else 0.25, 0.015, nh),
        "text-secondary": solve(0.02, nh, page, 7.5 if high else 5.2, True),
        "text-tertiary": solve(0.015, nh, page, 4.5 if high else 2.6, True),
        "separator": hexof(PAPER_L - (0.2 if high else 0.12), 0.012, nh),
        "tint": solve(fam["dayC"], nh, page, 9 if high else 7, True),
        "accent-fill": hexof(fam["fillL"] - (0.06 if high else 0), fam["fillC"], nh),
        "on-accent": page,
        "timeline-unplayed": hexof(PAPER_L - (0.2 if high else 0.13), C * 0.8 + 0.008, PAPER_H),
    }
    out["timeline-played"] = out["tint"]
    return out


def dark(fam, high):
    nh = fam["h"]
    page = hexof(HALL_L - (0.02 if high else 0), HALL_C * (0.6 if high else 1), nh)
    out = {
        "background-page": page,
        "background-grouped": page,
        "background-row": hexof(HALL_L + 0.04, HALL_C, nh),
        "background-elevated": hexof(HALL_L + 0.07, HALL_C, nh),
        "text-primary": solve(0.02, PAPER_H, page, 15 if high else 11.5, False),
        "text-secondary": solve(0.018, PAPER_H, page, 8 if high else 6, False),
        "text-tertiary": solve(0.012, PAPER_H, page, 4.5 if high else 2.8, False),
        "separator": hexof(HALL_L + (0.2 if high else 0.12), HALL_C, nh),
        "tint": solve(fam["nightC"], nh, page, 9 if high else 6.5, False),
        "accent-fill": hexof(fam["fillL"] - 0.04, fam["fillC"] * 0.9, nh),
    }
    out["on-accent"] = out["text-primary"]
    out["timeline-played"] = out["tint"]
    out["timeline-unplayed"] = mix(page, out["text-primary"], DARK_UNPLAYED_MIX[high])
    return out


def marks(values, fam, day, high):
    """The favourite and its quiet off state, Increase Contrast on every ground, translucent fills, swipe colours."""
    nh = fam["h"]
    text, mark = (HC_TEXT_FLOOR, HC_MARK_FLOOR) if high else (None, None)
    if high:
        secondary = (0.02, nh) if day else (0.018, PAPER_H)
        values["text-secondary"] = solve_on(*secondary, values, 7.5 if day else 8, text, day)
        chroma = fam["dayC"] if day else fam["nightC"]
        values["tint"] = values["timeline-played"] = solve_on(chroma, nh, values, 9, text, day)
    # The favourite is the accent at its strongest chroma that still clears its target.
    favourite = (7 if high else 4.5) if day else (9 if high else 6.5)
    values["favourite"] = solve_on(0.19, nh, values, favourite, mark, day)
    # Not set: a quiet neutral at the 3:1 floor for a control (4.5 in Increase Contrast).
    values["favourite-off"] = solve_on(0.012, PAPER_H if day else nh, values, 4.5 if high else 3.0, mark, day)
    # Fills are overlays: the Chronology draws its era bands over the composer lines.
    ink = "#3c3028" if day else "#f0e6d8"
    values["fill-standard"] = (ink, 0.16 if day else 0.2)
    values["fill-quiet"] = (ink, 0.08 if day else 0.11)
    target = 7 if high else 4.6
    for name, (h, c) in SWIPES.items():
        step = SWIPE_STEP if name in SWIPE_DARKER else 0.0
        values[f"swipe-{name}"] = solve(c, nh if h is None else h, "#ffffff", target, True, step)


def rooms(fam):
    out = {}
    for room, day, high in (
        ("light", True, False),
        ("lightHighContrast", True, True),
        ("dark", False, False),
        ("darkHighContrast", False, True),
    ):
        values = light(fam, high) if day else dark(fam, high)
        marks(values, fam, day, high)
        out[room] = values
    return out


# ---------- the token files ----------
# Token path in the palette for each solved colour, in file order.
LAYOUT = (
    ("background", ("page", "row", "grouped", "elevated")),
    ("text", ("primary", "secondary", "tertiary")),
    ("separator", None),
    ("fill", ("standard", "quiet")),
    ("tint", None),
    ("accent", ("fill",)),
    ("on-accent", None),
    ("favourite", None),
    ("favourite-off", None),
    ("timeline", ("played", "unplayed")),
    ("swipe", tuple(SWIPES)),
)


def key(group, name):
    if name is None:
        return group
    return "accent-fill" if group == "accent" else f"{group}-{name}"


def token(value):
    """One colour token on one line, so a changed colour is a one-line diff."""
    hx, alpha = value if isinstance(value, tuple) else (value, None)
    L, C, h = oklch(hx)
    colour = {"colorSpace": "srgb", "components": [round(c, 4) for c in channels(hx)], "hex": hx.upper()}
    if alpha is not None:
        colour["alpha"] = alpha
    body = {"$value": colour, "$extensions": {"de.whnr.klassik": {"oklch": [round(L, 3), round(C, 3), round(h, 1)]}}}
    return json.dumps(body, separators=(", ", ": "))


def document(name, fam):
    description = (
        f"Accent family {fam['label']}: every colour in the four themes. The theme files point the color tokens here. "
        "Generated by design/scripts/palette.py from contrast targets (ADR 0034, ADR 0037). Do not edit."
    )
    lines = ["{", f'  "$description": {json.dumps(description)},', '  "palette": {', '    "$type": "color",']
    solved = rooms(fam)
    for r, (room, values) in enumerate(solved.items()):
        lines.append(f'    "{room}": {{')
        for g, (group, names) in enumerate(LAYOUT):
            last_group = g == len(LAYOUT) - 1
            if names is None:
                lines.append(f'      "{group}": {token(values[key(group, None)])}' + ("" if last_group else ","))
                continue
            lines.append(f'      "{group}": {{')
            for n, name in enumerate(names):
                comma = "" if n == len(names) - 1 else ","
                lines.append(f'        "{name}": {token(values[key(group, name)])}{comma}')
            lines.append("      }" + ("" if last_group else ","))
        lines.append("    }" + ("" if r == len(solved) - 1 else ","))
    lines += ["  }", "}", ""]
    return "\n".join(lines)


def main():
    check = "--check" in sys.argv[1:]
    stale = []
    for name, fam in FAMILIES.items():
        path = DESIGN / f"accent-{name}.tokens.json"
        text = document(name, fam)
        if check:
            if not path.exists() or path.read_text() != text:
                stale.append(path)
        else:
            path.write_text(text)
            print(f"wrote {path.relative_to(ROOT)}")
    for path in stale:
        print(f"palette.py: {path.relative_to(ROOT)} is not current. Run design/scripts/palette.py.", file=sys.stderr)
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
