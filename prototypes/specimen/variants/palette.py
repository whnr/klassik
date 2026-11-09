"""Prototype for sz-rs30.1.83.19.1, round 22: writes one CSS file per accent family.

Throwaway. Each colour starts as OKLCH. Lightness is solved from its WCAG target on the
background it sits on, then the colour is gamut-mapped by lowering chroma at fixed L and hue.
Run: python3 variants/palette.py  (prints a WCAG and APCA report)
"""

import math
from pathlib import Path

HERE = Path(__file__).parent


# ---------- colour maths (Ottosson OKLab, WCAG 2, APCA 0.0.98G) ----------
def oklch_to_srgb(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_**3, m_**3, s_**3
    lin = (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )
    return lin


def in_gamut(lin):
    return all(-1e-4 <= c <= 1 + 1e-4 for c in lin)


def encode(c):
    c = min(max(c, 0.0), 1.0)
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def hexof(L, C, h):
    while C > 0 and not in_gamut(oklch_to_srgb(L, C, h)):
        C -= 0.001
    r, g, b = (round(encode(c) * 255) for c in oklch_to_srgb(L, max(C, 0), h))
    return f"#{r:02x}{g:02x}{b:02x}"


def channels(hx):
    return [int(hx[i : i + 2], 16) / 255 for i in (1, 3, 5)]


def lum(hx):
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in channels(hx)]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def wcag(a, b):
    x, y = sorted([lum(a), lum(b)])
    return (y + 0.05) / (x + 0.05)


def apca(text, bg):
    def y(hx):
        r, g, b = (c**2.4 for c in channels(hx))
        v = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        return v if v > 0.022 else v + (0.022 - v) ** 1.414

    yt, yb = y(text), y(bg)
    if yb > yt:
        s = (yb**0.56 - yt**0.57) * 1.14
        return 0 if s < 0.1 else (s - 0.027) * 100
    s = (yb**0.65 - yt**0.62) * 1.14
    return 0 if s > -0.1 else (s + 0.027) * 100


def solve(C, h, bg, target, darker, step=0.0):
    """The lightness nearest the background that still reaches the target ratio, then step darker."""
    lo, hi = (0.0, 1.0)
    for _ in range(40):
        mid = (lo + hi) / 2
        ok = wcag(hexof(mid, C, h), bg) >= target
        if darker:
            lo, hi = (mid, hi) if ok else (lo, mid)
        else:
            lo, hi = (lo, mid) if ok else (mid, hi)
    return hexof((lo if darker else hi) - step, C, h)


# ---------- the families ----------
# h: accent hue. Day text is a deep jewel; night text is its lighter, quieter twin.
FAMILIES = {
    "claret": dict(label="Claret", h=6, dayC=0.13, nightC=0.11, fillL=0.38, fillC=0.12),
    "green": dict(label="Bottle green", h=160, dayC=0.09, nightC=0.09, fillL=0.40, fillC=0.08),
    "plum": dict(label="Plum", h=345, dayC=0.11, nightC=0.10, fillL=0.38, fillC=0.10),
}
# Swipe colours (sz-rs30.1.83.19.6): one hue per action, white labels. Favourite takes the favourite's hue.
# Add to Queue and Favourite sit OKLab L 0.12 darker, so a pair still differs for colour-blind eyes
# (docs/research/colour-vision.md on branch research/colour-vision).
SWIPES = {"swipe-playNext": (285, 0.10), "swipe-addToQueue": (60, 0.10), "swipe-download": (215, 0.10), "swipe-favourite": (None, 0.19)}
SWIPE_DARKER = {"swipe-addToQueue", "swipe-favourite"}
SWIPE_STEP = 0.12
PAPERS = {"faint": (0.972, 0.010), "middle": (0.966, 0.020), "creamy": (0.958, 0.032)}
PAPER_H = 85
HALL_L, HALL_C = 0.18, 0.010


def light(fam, paper, high):
    L, C = PAPERS[paper]
    if high:
        C *= 0.6
    page = hexof(L, C, PAPER_H)
    nh = fam["h"]
    out = {
        "background-page": page,
        "background-row": page,
        "background-grouped": hexof(L - 0.03, C * 1.2, PAPER_H),
        "background-elevated": hexof(min(L + 0.012, 0.99), C * 0.7, PAPER_H),
        "text-primary": hexof(0.18 if high else 0.25, 0.015, nh),
        "text-secondary": solve(0.02, nh, page, 7.5 if high else 5.2, True),
        "text-tertiary": solve(0.015, nh, page, 4.5 if high else 2.6, True),
        "separator": hexof(L - (0.2 if high else 0.12), 0.012, nh),
        "tint": solve(fam["dayC"], nh, page, 9 if high else 7, True),
        "accent-fill": hexof(fam["fillL"] - (0.06 if high else 0), fam["fillC"], nh),
        "on-accent": page,
        "timeline-unplayed": hexof(L - (0.2 if high else 0.13), C * 0.8 + 0.008, PAPER_H),
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
        "timeline-unplayed": hexof(HALL_L + (0.2 if high else 0.14), HALL_C + 0.006, nh),
    }
    out["on-accent"] = out["text-primary"]
    out["timeline-played"] = out["tint"]
    return out


def marks(values, fam, theme, high):
    """The strong favourite, its quiet off state, translucent fills and the swipe preview."""
    bg, nh, day = values["background-page"], fam["h"], theme == "light"
    # The favourite is the accent at its strongest chroma that still clears its target.
    values["favourite"] = solve(0.19, nh, bg, (7 if high else 4.5) if day else (9 if high else 6.5), day)
    # Not set: a quiet neutral at the 3:1 floor for a control (4.5 in Increase Contrast).
    values["favourite-off"] = solve(0.012, PAPER_H if day else nh, bg, 4.5 if high else 3.0, day)
    # Fills are overlays: the Chronology draws its era bands over the composer lines.
    ink = (0x3c, 0x30, 0x28) if day else (0xf0, 0xe6, 0xd8)
    for name, a in (("fill-standard", 0.16 if day else 0.2), ("fill-quiet", 0.08 if day else 0.11)):
        values[name] = "#%02x%02x%02x%02x" % (*ink, round(a * 255))
    target = 7 if high else 4.6
    for name, (h, c) in SWIPES.items():
        step = SWIPE_STEP if name in SWIPE_DARKER else 0.0
        values[name] = solve(c, nh if h is None else h, "#ffffff", target, True, step)


def block(selectors, values):
    body = "\n".join(f"  --color-{k}: {v};" for k, v in values.items())
    return ",\n".join(selectors) + " {\n" + body + "\n}\n"


def build(name, fam):
    sets = {}
    for paper in PAPERS:
        for high in (False, True):
            sets[("light", paper, high)] = light(fam, paper, high)
    for high in (False, True):
        sets[("dark", None, high)] = dark(fam, high)
    for (theme, _, high), values in sets.items():
        marks(values, fam, theme, high)
    css = [f"/* PROTOTYPE, round 22, sz-rs30.1.83.19.1: {fam['label']}. Written by palette.py. */\n"]
    for (theme, paper, high), values in sets.items():
        c = "high" if high else "normal"
        if theme == "light":
            sel = [f':root[data-paper="{paper}"][data-theme="light"][data-contrast="{c}"]', f':root[data-paper="{paper}"] [data-theme="light"][data-contrast="{c}"]']
        else:
            sel = [f':root[data-theme="dark"][data-contrast="{c}"]', f':root [data-theme="dark"][data-contrast="{c}"]']
        css.append(block(sel, values))
    (HERE / f"palette-{name}.css").write_text("\n".join(css))
    return sets


def report(name, sets):
    print(f"\n{name}")
    for (theme, paper, high), v in sets.items():
        if paper not in (None, "middle"):
            continue
        bg = v["background-page"]
        pairs = [("text", v["text-primary"], bg), ("2nd", v["text-secondary"], bg), ("tint", v["tint"], bg),
                 ("fav", v["favourite"], bg), ("off", v["favourite-off"], bg), ("label", v["on-accent"], v["accent-fill"]),
                 ("played/unpl", v["timeline-played"], v["timeline-unplayed"]), ("fill/page", v["accent-fill"], bg)]
        row = "  ".join(f"{n} {wcag(a, b):4.1f}/{abs(apca(a, b)):3.0f}" for n, a, b in pairs)
        print(f"  {theme:5} {'HC' if high else '  '} page {bg} tint {v['tint']}  {row}")


if __name__ == "__main__":
    for name, fam in FAMILIES.items():
        report(name, build(name, fam))
