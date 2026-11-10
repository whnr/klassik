# 0036. The design folder and its checks

Date: 2026-11-10. Decided by Flo on PR #13. Bead: sz-rs30.1.83.25. Replaces the script path and the lint rule of [0021](0021-design-tokens.md).

## Context

PR #13 brings every design decision to `main`: the token files, the font, the fermata and the specimen pages. Most of its lines are data and generated files. Nothing proved that the values still meet the contrast targets of [0034](0034-colour.md), that the ADR links resolve, or that the specimen pages run. No tool formatted or linted the Python, HTML, CSS or JavaScript. The Swift lint job runs in a Swift image without Python, so the token check in `scripts/lint.sh` failed there.

## Decision

- `design/` holds the whole design system: the token files, `design/tokens.css`, the font, the fermata, the specimen and the scripts in `design/scripts/`. `tokens.py` moves there from `scripts/`.
- `design/specimen/` is the design reference. It shows only decided values. The UI tracer builds against it; when a view exists in SwiftUI, the SwiftUI code is the truth, as [0021](0021-design-tokens.md) says.
- `design/scripts/lint.sh` runs every check: Ruff format and lint for all Python, Prettier format for the HTML, CSS, JavaScript and JSON in `design/`, Biome lint for the JavaScript, the inline scripts included, then `tokens.py --check`, the contrast and link check `check.py`, and `specimen_check.py`, which opens every specimen page in headless Chromium and taps a row.
- uv runs every Python step (`uvx ruff`, `uv run --with playwright`). Prettier and Biome run through `npx`. Each tool has a pinned version. There is no `package.json` and no virtual environment in the repository.
- Generated files are not formatted: `design/tokens.css`, the accent palettes and the specimen data.
- Workflow `design.yml` runs the script on Linux, only when the design, the ADRs, the Python or the tool configs change. It is not a required check, so a skipped run never blocks a merge. `scripts/lint.sh` checks Swift only.

## Consequences

- The contrast check lists the standard pairs below AA as known until bead sz-rs30.1.83.19.17 decides. A new pair below its target fails.
- Biome lints the inline scripts through its experimental full HTML support. A Biome update can change its findings; the version stays pinned until someone updates it on purpose.
- The checks cannot judge looks or Safari. Flo's phone stays the judge for both.
