# 0014. The player: rows beside one timeline

Date: 2026-11-02. Decided by Flo after seven prototype rounds. Bead: sz-rs30.1.74.7. Changes the player part of sz-rs30.1.74.4: the player is no longer a sheet, and the mini player is no longer the plain tab accessory. The player that slides in on top, and the mini player that opens it, are replaced by [0015](0015-player-page.md). The row and note rules are replaced by [0027](0027-player-rows.md).

## Context

The idea was a vertical player: each movement a block, progress from top to bottom, the view scrolling with the music. On the phone, blocks sized by duration, a moving playhead and automatic scrolling felt busy. Flo wants the player quiet and calm, with every change in place. A work can have 32 movements of 12 seconds to 10 minutes. An album holds many works by many composers.

## Decision

- The **timeline** is one bar on the screen edge, always on screen, in every place and in the player. It shows the whole work or album, one segment for each movement or track, the played part in colour. It never slides.
- On the timeline, a vertical drag scrubs. A tap starts the movement under the finger from its beginning. A sideways swipe changes nothing. The timeline never opens the player.
- The listener puts the timeline on the right or the left edge. Right is the default.
- The **mini player** joins the timeline as one shape: a card with a flat face on the timeline's side. It shows the cover and three lines: movement, work, people (composer and conductor). A long movement title scrolls as a marquee. It has no progress line. A tap on it opens the player.
- A surname comes from the artist's sort name. Without a sort name, the full name shows. No rule shortens a title or a name.
- The **player** slides in beside the timeline. It shows the cover, the title and the performers that the whole work or album shares, then one row for each movement or track. Playing an album shows the album.
- A row shows its full title and its duration. A tap on a row opens it; it never plays. An open row plays from a round button in the place of its chevron.
- The playing row stays open. Below its title: the performers that differ from the whole, one row each; the movement's own bar with its controls; then its listening notes under the label "Notes".
- Changes happen in place: a tapped row does not move. The view scrolls by itself only after a quiet spell without touches. It then places the playing row in the upper part, with the previous title above it. Arrows bring the listener back at any time.
- A listening note shows on the movement's bar: a dot for a moment, a line for a span. Overlapping notes stack in lines above the bar. A span reads as start plus duration. A tap on a note jumps there; a tap on its time jumps there and plays.

## Consequences

- The tab accessory and the sheet of SwiftUI do not draw this. The timeline and the mini player are custom views over the `TabView`.
- On the left edge, the timeline sits where the system back swipe starts. The back swipe is horizontal, so it does not scrub, but the tracer must check it.
- The client needs per-track contributors with roles, and artist sort names, from OpenSubsonic. Notes stay on the device (ADR 0013).
- Layout, colours and type are not decided here. They belong to the design system map (sz-rs30.1.83).
