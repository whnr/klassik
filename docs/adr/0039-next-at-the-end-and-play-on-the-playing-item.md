# 0039. Next ends at the last movement; Play on the playing item pauses or resumes

Date: 2026-11-11. Decided by Flo after the slice 3 review (PR #16). Bead: sz-rs30.1.105.20. Replaces the rule of [0006](0006-queue.md) that Play replaces the queue, for the item that already plays. Adds to the Next rule of [0014](0014-player.md).

## Context

ADR 0006 says that Play replaces the queue. ADR 0014 says that a tap on the tinted row of the playing recording pauses and resumes it. The work page and the context menu also have a Play button. On the recording that already plays, that button had no rule. Next on the last movement of the last item did nothing, and the button looked active.

## Decision

- On the last movement of the last queue item, Next is off. This holds in the app and on the lock screen.
- Play on the item that already plays pauses it, or resumes it when paused. This is the same as a tap on its tinted row.
- Play on any other item replaces the queue, as in ADR 0006.
- The full redesign will replace Play with a Pause button on the playing item.

## Consequences

- A Play button can pause. Its label stays "Play" until the redesign.
- The queue still ends when the last movement ends. Next never ends it.
