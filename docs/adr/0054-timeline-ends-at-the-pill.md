# 0054. The timeline ends at the top of the pill

Decided by Flo in the 0.14.1 test notes, 2026-11-17. Bead: sz-3hcq.3.
This replaces the strip rules of [0041](0041-native-tabs-and-display-corners.md).

## Context

The timeline strip ran on beside the mini player and followed the display corner. It ended below the pill. Flo: "Let's crop the timeline at the top of the pill. Not running on the side at all. Keep the cover art where it is today."

## Decision

- The timeline ends at the top of the mini player pill.
- No strip runs beside the pill or along the display corner.
- The square cover keeps its place above the display corner.

## Consequences

- The pill alone is the end of the timeline (ADR 0028).
- The display corner geometry places only the cover.
