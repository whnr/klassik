# 0045. Page margins follow the timeline

Date: 2026-11-17. Decided by Flo after the 0.14.1 build. Bead: sz-3hcq.11.

## Context

The content pages had 16 pt on the side away from the timeline and 32 pt on the timeline side, also when no
timeline showed. The timeline is 8 pt wide (ADR 0035). Flo found that the margins made no sense: the content was
not centred.

Flo's decision: "the content left after subtracting the timeline gets even margins left and right; ignore the
scroll bar. Timeline on the left: increase the left margin by the timeline width. Timeline on the right: increase
the right margin. Without timeline: 20/20."

## Decision

- With the timeline on the right, a content page has 16 pt on the left and 24 pt on the right: `space-l`, and
  `space-l` plus the timeline width.
- With the timeline on the left, the sides change: 24 pt on the left and 16 pt on the right.
- Without a timeline, a content page has 20 pt on both sides: `space-l` plus half the timeline width.
- The scroll indicator does not count. It keeps its place beside the timeline (ADR 0029).
- The specimen sets these values in `specimen.css` with the class `has-timeline`. `Klassik/Layout.swift` cites them.
- Settings and sheets keep the system insets.

## Consequences

- The content has the same width with and without a timeline. When playback starts or ends, the content moves
  4 pt to the side and does not wrap again.
- The timeline shows while an item plays. The margins change with it.
