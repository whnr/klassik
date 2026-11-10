# 0035. The timeline: flush, round on the content side, a gap for each movement

Date: 2026-11-10. Decided by Flo after specimen round 25 on the phone. Bead: sz-rs30.1.83.21. Adds the shape to the timeline of [0014](0014-player.md). Replaces the dark unplayed colour of [0034](0034-colour.md).

## Context

The specimen drew the timeline with hard edges, and it looked stuck to the side. On the Matthäus-Passion, 68 movements with a gap each made a ladder. Notches without gaps were tried in a drawing and did not separate movements at all. The top of the bar meets the rounded screen corner only if it enters the status bar.

## Decision

- The bar is 8 pt wide and flush with the screen edge. The edge side is straight.
- Each segment is round on the content side only, with radius `radius.xs` (4 pt).
- A gap of `space.xxs` (2 pt) separates every segment. A new work gets the same gap as a new movement.
- The bar starts at the top safe area, below the status bar. The first segment grows out of the screen edge in a curve of `size.timelineCap` (8 pt). The screen corner curve ends above the safe area, so the bar never meets it.
- The bar ends above the mini player, as before.
- In the dark room the unplayed part is a 32% OKLab mix of text into the page, about 2:1 (30% with Increase Contrast). This is an exception to the locked colours of [0034](0034-colour.md), for the timeline only. The played part keeps 3:1 from it, 4.5:1 with Increase Contrast.
- Over a picture with Increase Contrast, each segment gets a 2 pt keyline in the page colour, paper colour in the dark room.

## Consequences

- Rejected in round 25: a 1 pt hairline between movements with a 4 pt gap between works, and square cuts with round corners only at a work's ends.
- A work with many short movements spends much of the bar on gaps. Flo accepted this on the Passion.
- The UI tracer (sz-4k87) draws the segments as one custom shape and reads the safe area for the start.
