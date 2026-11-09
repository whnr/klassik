# 0032. The fermata: one solid drawing, grey when not set

Date: 2026-11-08. Decided by Flo after two fermata rounds on the phone. Bead: sz-rs30.1.83.18. Replaces the outline rule of [0017](0017-composer-and-performer-pages.md). Settles the drawing that [0030](0030-type-and-spacing.md) left open.

## Context

The favourite mark is a fermata (ADR 0017), drawn by Klassik as a custom SF Symbol (ADR 0030). Round 1 showed ten new shapes in three looks for a mark that is not set: solid grey, a round outline and a faint tint. Flo kept the specimen's first drawing. At its first size, 0.41 em, the mark was too small beside the title. Round 2 showed five heights, from 0.41 em to a capital O.

## Decision

- The drawing is a solid arc over a dot. On a 24 × 16 grid: the outer arc has radius 10.5 from (1.5, 14.5) to (22.5, 14.5). The inner edge is an ellipse arc, 8.6 by 7.2. The feet are flat on the baseline, 1.9 wide. The dot has radius 2.1, at (12, 12.4).
- Set: the solid drawing in the favourite colour.
- Not set: the same solid drawing in secondary text colour. No outline.
- The arc is 0.64 em high, about nine tenths of the SF cap height. It is twice as wide as high. It scales with the text that it follows.
- The feet sit on the text baseline, a quarter em after the last word.
- One weight for all text. The arc does not grow heavier beside bold text or with Bold Text on.

## Consequences

- Set and not set differ only in colour. The VoiceOver label carries the state.
- The SF Symbol template draws the arc below the cap-height guide.
