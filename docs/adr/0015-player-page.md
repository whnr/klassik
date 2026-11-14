# 0015. The player is the page of what plays

Date: 2026-11-03. Decided by Flo after three prototype rounds. Bead: sz-rs30.1.74.10. Annulled by Flo on 2026-11-14 (bead sz-rs30.1.105.8.1). His reason: this record fitted one stack that popped back. With one stack for each place, player pages pile up in every stack, in random places, and that confuses him. [0014](0014-player.md) is the record again. It holds the rules of this record that stay. This text stays as it was and no longer decides.

## Context

The player of ADR 0014 showed a cover, the shared performers and one row for each movement. The recording page showed the same things beside its own player card. Testers called that one screen work, recording, player and album. A player on top of the stack also needed its own close button and its own way back.

## Decision

- The player is the recording page or album page of the queue item that plays. Play on a recording page or album page turns that page into the player in place. Back works as on any page.
- The player page is washed in a colour from its cover. A cover without colour gives a wash in Klassik's tint, so the player never looks like a plain page.
- The mini player is a link to the player page. It pushes that page onto the current place's stack, or jumps back to it when it is already there. The mini player does not show on the player page. The timeline stays.
- Play on the work page plays the reference recording and stays on the work page. The row of that recording is tinted, and its slot pauses and resumes.
- The player page ends with a row for the next queue item. When an item ends, that row rises to the top and becomes the next item's page. The old content leaves upwards. No page goes onto the stack.
- Next on the last movement goes on to the next queue item. Klassik 1.0 has no way back to the previous item.
- Play replaces the queue (ADR 0006). Playing a movement of the item that already plays only moves the position.
- At the end of the queue, playback stops like a record. On the player page, the page stays and says that the queue has ended. Elsewhere the mini player and the timeline go away.

## Consequences

- The player and the recording page are one view, so the inline player card of today's recording page goes.
- The system back swipe now matters on the player page. With the timeline on the left edge, the tracer must check that the swipe does not scrub.
- A way back to the previous work and a Queue page wait for later (Klassik: playlists, sz-rs30.1.85; previous work, discovery for 1.1).
- Layout, colours and type are not decided here. They belong to the design system map (sz-rs30.1.83).
