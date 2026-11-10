# 0021. Design tokens in the repository

Date: 2026-11-05. Decided by Flo after research. Beads: sz-rs30.1.83.1, sz-rs30.1.83.3. The script path and the lint rule are replaced by [0036](0036-design-folder-and-checks.md).

## Context

Agents build and change Klassik's design. Flo judges it on his phone through HTML prototypes, and SwiftUI builds it later. Research compared three sources of truth: a token file in the repository, the claude.ai Design System artifact, and Figma. Only the token file lets an agent or CI read and write it without a person. The artifact has no place for motion and no route to SwiftUI. Figma needs paid seats and a browser sign-in, and it keeps the design outside the public repository.

## Decision

- The source of truth is one token file in DTCG 2025.10 format on `main`. It holds decided values only. A prototype variant overrides values inside the prototype. The winning values reach `main` when Flo decides the ticket.
- Agents edit the file. Flo judges the result on his phone.
- `scripts/tokens.py` uses the Python standard library only. It writes CSS for the prototypes and the Swift and asset files for the app. Its output is committed, and `scripts/lint.sh` fails when the output is not current.
- Colours go into the asset catalog as colour sets, with light, dark and high-contrast values. The system then knows them: the global accent colour, the launch screen, and later widgets. The script also writes a Swift file with one typed name for each colour, so a wrong name in a view stops the build. A unit test loads each colour in light, dark and high contrast and compares it with the token file.
- Asset symbol generation stays off. The typed names give the same check without the 40 s of each CI build.
- Type tokens map to system text styles, so Dynamic Type works. Spacing scales with `ScaledMetric`. Motion tokens become SwiftUI animations that respect Reduce Motion.
- No Figma. No Design System artifact. The specimen shows the design, with a token sheet for the values that its four screens do not show.
- A drawn view (timeline bar, Chronology, fermata) is drawn in HTML while it is decided. A design reference on `main` then describes it. The HTML is thrown away, and the SwiftUI code becomes the truth.

## Consequences

- The colour-set key for dark values is not in Apple's archived format reference. The unit test proves it on CI.
- Contributors change the design through the token file and the script, never in Xcode's colour editor.
