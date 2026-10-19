"""Compares the screenshots of a UI walk with a baseline and writes a report for a reader who cannot look at all of them.

Writes diff.md (one row per screen, largest change first), diff.json, and for each changed screen a PNG with
three panels at one pixel per point: baseline, current, and current with the changed pixels in red.
Usage: python3 scripts/screen_diff.py <baseline-dir> <current-dir> <out-dir>
The baseline directory may hold sources.json: {"<screen>.png": "<run, commit>"}.
"""
import json, pathlib, sys

import numpy as np
from PIL import Image

SCALE = 3  # Simulator screenshots of an iPhone are at 3x; the report gives points, as the SwiftUI code does.
TOLERANCE = 24  # Largest channel difference that still counts as the same pixel: text antialiasing jitter.
SMALL = 0.5  # Percent of changed pixels below which a change is "small".
MERGE = 8  # Points between changed rows that still belong to one region.

# Rectangles in points (x, y, width, height) that change on every walk. Keep them tight: a mask hides real changes.
MASKS = {
    "11-diagnostics": [(140, 610, 262, 45)],  # "Last check" time.
    "12-diagnostics-bottom": [(0, 50, 402, 60)],  # "Last sync" time, blurred under the navigation bar.
}


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def regions(changed):
    """Groups changed rows into bands and gives each band's box in points."""
    rows = np.flatnonzero(changed.any(axis=1))
    bands, start, last = [], None, None
    for y in rows:
        if start is not None and y - last > MERGE * SCALE:
            bands.append((start, last))
            start = None
        if start is None:
            start = y
        last = y
    if start is not None:
        bands.append((start, last))
    boxes = []
    for top, bottom in bands:
        cols = np.flatnonzero(changed[top : bottom + 1].any(axis=0))
        boxes.append(
            tuple(int(v) // SCALE for v in (cols[0], top, cols[-1] - cols[0] + 1, bottom - top + 1)),
        )
    return boxes


def panel(base, current, changed):
    marked = (current * 0.35 + 165).astype(np.uint8)
    marked[changed] = (255, 0, 0)
    images = [Image.fromarray(a.astype(np.uint8)) for a in (base, current, marked)]
    w, h = images[0].width // SCALE, images[0].height // SCALE
    out = Image.new("RGB", (3 * w + 2 * 8, h), "white")
    for i, image in enumerate(images):
        out.paste(image.resize((w, h), Image.LANCZOS), (i * (w + 8), 0))
    return out


def compare(base_path, current_path):
    base, current = load(base_path), load(current_path)
    if base.shape != current.shape:
        return {"band": "large", "percent": 100.0, "regions": [], "note": f"size {base.shape[:2]} → {current.shape[:2]}"}, None
    changed = np.abs(base - current).max(axis=2) > TOLERANCE
    for x, y, w, h in MASKS.get(current_path.stem, []):
        changed[y * SCALE : (y + h) * SCALE, x * SCALE : (x + w) * SCALE] = False
    percent = round(float(100 * changed.mean()), 2)
    if not changed.any():
        return {"band": "same", "percent": 0.0, "regions": []}, None
    band = "small" if percent < SMALL else "large"
    return {"band": band, "percent": percent, "regions": regions(changed)}, panel(base, current, changed)


def main(base_dir, current_dir, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    sources_file = base_dir / "sources.json"
    sources = json.loads(sources_file.read_text()) if sources_file.exists() else {}
    current = {p.name: p for p in sorted(current_dir.glob("*.png"))}
    base = {p.name: p for p in sorted(base_dir.glob("*.png"))}
    report = {}
    for name, path in current.items():
        if name not in base:
            report[name] = {"band": "new", "percent": 100.0, "regions": []}
            continue
        result, image = compare(base[name], path)
        result["baseline"] = sources.get(name, "")
        if image:
            result["panel"] = f"{path.stem}-diff.png"
            image.save(out_dir / result["panel"], optimize=True)
        report[name] = result
    (out_dir / "diff.json").write_text(json.dumps(report, indent=1, ensure_ascii=False))

    order = {"new": 0, "large": 1, "small": 2, "same": 3}
    rows = sorted(report.items(), key=lambda kv: (order[kv[1]["band"]], -kv[1]["percent"], kv[0]))
    look = [n for n, r in rows if r["band"] in ("new", "large")]
    small = [n for n, r in rows if r["band"] == "small"]
    same = [n for n, r in rows if r["band"] == "same"]
    lines = [
        "# Screenshot diff",
        "",
        f"{len(current)} screens: {len(look)} to look at, {len(small)} small, {len(same)} same.",
        "Look at each *-diff.png of a new or large row: baseline | current | changed pixels in red.",
        "Look at a small row only if the push meant to change that screen.",
        f"Regions are x,y,width,height in points; 0,0 is the top left of a {base_or_current_size(current)} screen.",
        "",
        "| Screen | Band | Changed | Regions | Baseline |",
        "|---|---|---|---|---|",
    ]
    for name, r in rows:
        if r["band"] == "same":
            continue
        boxes = "; ".join(",".join(map(str, b)) for b in r["regions"][:5])
        if len(r["regions"]) > 5:
            boxes += f"; +{len(r['regions']) - 5} more"
        boxes = r.get("note", boxes)
        percent = "<0.01" if 0 < r["percent"] < 0.01 else r["percent"]
        lines.append(f"| {name[:-4]} | {r['band']} | {percent} % | {boxes} | {r.get('baseline', '')} |")
    if same:
        lines += ["", "Same: " + ", ".join(n[:-4] for n in same)]
    missing = sorted(set(base) - set(current))
    if missing:
        lines += ["", "Not walked in this run: " + ", ".join(n[:-4] for n in missing)]
    (out_dir / "diff.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


def base_or_current_size(current):
    if not current:
        return "?"
    w, h = Image.open(next(iter(current.values()))).size
    return f"{w // SCALE}×{h // SCALE} pt"


if __name__ == "__main__":
    main(*map(pathlib.Path, sys.argv[1:4]))
