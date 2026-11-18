# 0053. The queue end and Stop close the player

Decided by Flo in the 0.14.1 test notes, 2026-11-17. Bead: sz-3hcq.1.
This replaces the queue end rule of [0014](0014-player.md).

## Context

The open player showed "The queue has ended." or "Playback stopped." at its foot when nothing played. Flo: "It's a tiny useless message." On the queue end: "Well just close the player."

## Decision

- When the queue ends, the player closes.
- When the listener taps Stop, the player closes.
- The player shows no end message.
- As before, the mini player and the timeline go away when nothing plays.

## Consequences

- The player exists only while something plays. A closed player restores the page underneath, as a slide down does.
- The app closes the player when the playback session has no item.
