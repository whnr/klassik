# 0037. The palette is solved from its targets on main

Date: 2026-11-10. Decided by Flo on PR #13. Bead: sz-rs30.1.83.25. Replaces where the colour values of [0034](0034-colour.md) come from. [0021](0021-design-tokens.md) still holds for every other token.

## Context

The three accent files held 252 colours in 5,250 lines, about 20 lines for each colour. The decision behind them is a short list: the hues and chromas of each family, the paper and the hall, and the contrast targets of 0034. The solver that turned that list into colours lived only on branch `prototypes`.

## Decision

- `design/scripts/palette.py` holds the decision as constants: the families, the paper, the hall, the swipe hues, the targets, the Increase Contrast floors and the dark timeline mix of [0035](0035-timeline-shape.md).
- It solves every colour and writes `design/accent-*.tokens.json`, one line for each colour. The files are generated output: nobody edits them.
- `palette.py --check` fails when a file is not current. `design/scripts/lint.sh` runs it before `tokens.py --check`.

## Consequences

- A changed target or hue is a one-line change in `palette.py`. The review sees the new colours as one line each.
- The OKLCH value beside each hex is measured from the hex, so it can differ slightly from the solver's input.
- The solver reproduced all 252 decided colours exactly when it moved to `main`.
