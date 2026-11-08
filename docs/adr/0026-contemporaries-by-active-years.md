# 0026. Contemporaries by overlapping active years

Date: 2026-11-07. Decided by Flo after the fourth specimen round. Bead: sz-rs30.1.83.12. Replaces one rule of [0016](0016-chronology.md).

## Context

ADR 0016 made a contemporary a composer with works in the library dated inside the focus composer's window. Many libraries hold works without a composition date. In the specimen, Bach's and Handel's works had no date, so Vivaldi showed alone. A composer is a contemporary because their working lives overlap, not because the library holds a dated work from those years.

## Decision

- A contemporary is a composer in the library whose active years overlap the window of the composer in focus.
- The window is the focus composer's active years, 10 years before and after. Without a work period start (P2031), the window is the whole life, without a buffer (ADR 0016).
- A contemporary's own active years run from their work period start to their death. Without a work period start, they are the whole life.
- The dates of the works do not decide who is a contemporary. A contemporary's dated works still show as dots on their line.

## Consequences

- A contemporary needs life dates from Wikidata. A composer without life dates stays off the chart, as before.
- More lines show at the composer level. The tracer checks that the lanes stay readable for a crowded period.
