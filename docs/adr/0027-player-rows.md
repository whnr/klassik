# 0027. Player rows: play at the end, open only what differs

Date: 2026-11-08. Decided by Flo after specimen round 6 on the phone. Bead: sz-rs30.1.83.8. Replaces the row and note rules of [0014](0014-player.md). The timeline, the mini player and the auto-scroll of 0014 stay.

## Context

ADR 0014 played a movement only from an open row: a tap opened the row, and a round button replaced its chevron. On the phone, an opened row grew a little and showed nothing else. Most movements hold nothing that the page does not already show. In the specimen data, no movement credits a performer that differs from its page. Only listening notes fill an opened row.

## Decision

- Every movement row that does not play shows a faint round play button at its trailing edge. A tap on it plays from the start of that movement. The button stays at the trailing edge with the timeline on either side.
- A row opens only when it holds something: listening notes, or names that differ from the page header. Such a row shows the disclosure chevron of a list disclosure group at its trailing edge, before the play button. A tap on the row opens or closes it in place. A row with nothing to show does not react to a tap.
- The page header shows what every track shares: composer, performers, the album and the year. An opened row shows only what differs for its track, one name per row with its role.
- A recording shows the year its tracks carry. The album year can belong to another recording in a box set.
- Only the playing movement has a playback bar. No other row, card or sheet shows one.
- An opened row shows no facts such as movement number, track number or recording year.
- A listening note is written in the playing row, never in a modal. One tap on "Add a note here" starts the note at the playing time and opens the text field. "End here" is optional and turns the note into a span; an end before the start swaps the two. The note stays open until Save or Return, so the listener can scrub the movement bar or the timeline to find the end.
- A scrub on the timeline holds the rows still until the finger lifts.

## Consequences

- A view that always shows every row's content, with nothing to open, stays a later option.
- Editing and deleting a note is open: bead sz-rs30.1.96.
- The look of the disclosure chevron is not decided. The design map checks the system control of the target iOS release.
- The tracer finds the system disclosure control that sits next to a trailing button in a row, or draws one that matches it.
