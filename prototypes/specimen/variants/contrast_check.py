"""Prototype for sz-rs30.1.83.19.12: proves every Increase Contrast pair that palette.py writes.

Text and links reach 7:1 and marks 4.5:1 on every ground: page, row, grouped and elevated.
The unplayed timeline is not checked against the ground. The played part reaches 9:1 on the page
and 4.5:1 from the unplayed part, so the unplayed part cannot also reach 4.5:1 on the page.
Run: python3 variants/contrast_check.py  (exits 1 on a failed pair)
"""

import sys

import palette as P

TEXT = ("text-primary", "text-secondary", "tint")
MARKS = ("favourite", "favourite-off", "timeline-played")
SWIPES = ("swipe-playNext", "swipe-addToQueue", "swipe-download", "swipe-favourite")


def sets(fam):
    for paper in P.PAPERS:
        yield "light", paper, P.light(fam, paper, True)
    yield "dark", "", P.dark(fam, True)


fails = 0
for name, fam in P.FAMILIES.items():
    for theme, paper, v in sets(fam):
        P.marks(v, fam, theme, True)
        pairs = [(v[t], v[g], 7) for t in TEXT for g in P.BACKGROUNDS]
        pairs += [(v[m], v[g], 4.5) for m in MARKS for g in P.BACKGROUNDS]
        pairs += [(v["on-accent"], v["accent-fill"], 7), (v["timeline-played"], v["timeline-unplayed"], 4.5)]
        pairs += [("#ffffff", v[s], 7) for s in SWIPES]
        low = min(P.wcag(a, b) / t for a, b, t in pairs)
        bad = [(a, b, t) for a, b, t in pairs if P.wcag(a, b) < t - 0.005]
        fails += len(bad)
        print(f"{name:6} {theme:5} {paper:6} {len(pairs)} pairs, weakest at {low:.2f} of target" + (f", {len(bad)} FAIL" if bad else ""))
        for a, b, t in bad:
            print(f"    {a} on {b}: {P.wcag(a, b):.2f} < {t}")
sys.exit(1 if fails else 0)
