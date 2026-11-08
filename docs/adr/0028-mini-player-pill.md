# 0028. The mini player is a pill at the end of the timeline

Date: 2026-11-08. Decided by Flo after specimen round 7 on the phone. Bead: sz-rs30.1.83.9. Replaces the mini player of [0014](0014-player.md) and the rule of [0015](0015-player-page.md) that the mini player does not show on the player page.

## Context

The card of ADR 0014 floated above the content in every place. It took a row of height from every page. A review found no plain pause button. Classical listening stays on one work for a long time, so the mini player needs little text. Round 7 showed four shapes: a pill with play/pause beside the cover, the same pill stacked on the edge, play/pause in the tab capsule, and the card with a pause button. Album art is square, so a round cover reads wrong. That ruled out the stacked pill.

## Decision

- The **mini player** is a pill in the tab bar row, on the timeline's side. It holds a round play/pause button and the square cover. The cover sits at the screen edge.
- The timeline bar runs into the pill's flat face. The pill is the end of the timeline.
- The pill shows no text. The scrub label and the player page name what plays.
- A tap on the cover opens the player page, as in ADR 0015. A tap on play/pause pauses or resumes, and stays on the page.
- The tab bar gets narrower to make room for the pill. It keeps its height.
- On the player page, the pill holds only play/pause.
- When nothing plays, the pill and the timeline go away (ADR 0015).

## Consequences

- Pages get back the height of the card. At large Dynamic Type sizes, the mini player no longer grows.
- The system `TabView` draws its tab bar across the full width. The tracer checks whether iOS 27 leaves room beside it. If not, the tab bar is drawn by hand.
- The tab items are about 64 points wide on a 393-point screen. The tracer checks the tap targets on a device.
- The Search page layout is open: sz-rs30.1.83.13.
- The look of the pill (glass, colours, the strip on its flat face) belongs to the colour ticket.
