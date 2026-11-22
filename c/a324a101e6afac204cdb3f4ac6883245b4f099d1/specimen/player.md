# Player, timeline and mini player

Rules for `player.html`, `overlay.*`, `pill.*`, `timeline.css` and `cover.*`. The specimen shows them. This note gives the rules that a picture cannot show.

## Queue

- A queue item is one recording of one work, or one whole album.
- Play replaces the queue. Play Next and Add to Queue add to it, as in Apple Music.
- Play on the item that plays pauses it, or resumes it when paused. A tap on its tinted row does the same.
- After the last movement of an item, the next item starts. Two items never join without a gap.
- On the last movement of the last item, Next is off, in the app and on the lock screen. Klassik 1.0 has no way back to the previous item.
- No Shuffle before 1.0. After 1.0 it comes back as discovery, not as shuffle.
- The queue lives on the device.

## Player overlay

- The player is an overlay, not a page. It never goes onto a stack, so it exists once above all places. A recording page or album page stays a page of its place.
- It slides up from the bottom and fills the display, both safe areas included. The cover of the mini player opens it.
- A slide down closes it and restores the page underneath, with its scroll position.
- Any tab tap closes it and restores the last page of that tab, also the tab underneath. It never returns to the root of the tab.
- The native tab bar and the whole pill stay visible above the overlay. The pill keeps play/pause, its square cover, its size and its place. The timeline stays on its edge.
- When the queue ends or the listener taps Stop, the player closes. It shows no end message.
- The player ends with a row for the next queue item. When an item ends, that row rises to the top and the player shows that item.
- Play on the work page plays the reference recording and opens no player. The row of that recording is tinted.

## Movement rows

- A row shows its full title and its duration. No rule shortens a title or a name.
- Every row that does not play shows a faint round play button at its trailing edge, with the timeline on either side. A tap on it plays from the start of the movement.
- A row opens only when it holds something: listening notes, or names that differ from the page header. Such a row shows the disclosure chevron before the play button. A tap on the row opens or closes it in place. Other rows do not react to a tap.
- The header shows what every track shares: composer, performers, album and year. An opened row shows only what differs, one name per line with its role. It shows no movement number, track number or recording year.
- A recording shows the year that its tracks carry, because the album year can belong to another recording of a box set.
- Only the playing movement has a playback bar. The playing row has no bold title.
- Changes happen in place: a tapped row does not move. The view scrolls by itself only after a quiet spell without touches. It then places the playing row in the upper part, with the previous title above it.
- A scrub on the timeline holds the rows still until the finger lifts.

## Listening notes

- A note shows on the bar of its movement: a dot for a moment, a line for a span. Notes that overlap stack in lines above the bar.
- A tap on a note jumps there. A tap on its time jumps there and plays.
- A note is written in the playing row, never in a modal. "Add a note here" starts it at the playing time and opens the text field. "End here" is optional and makes a span; an end before the start swaps the two. The note stays open until Save or Return, so the listener can scrub to find the end.

## Album page

- An album page heads its tracks by work only when one work has two movements on consecutive tracks. Otherwise it is a plain list of tracks in disc order, each title as tagged. A heading above one single piece makes the list twice as long for nothing.

## Timeline

- One bar on the screen edge, in every place and in the player. It shows the whole work or album, one segment for each movement or track. It never slides and never opens the player.
- A vertical drag scrubs. A tap starts the movement under the finger from its beginning. A sideways swipe changes nothing.
- The listener puts it on the right (default) or the left edge.
- The bar is 8 pt wide and flush with the edge. Each segment is round on the content side only (`radius.xs`). A gap of `space.xxs` separates every segment; a new work gets the same gap. A work with many short movements spends much of the bar on gaps. Flo accepted this on the Matthäus-Passion.
- The bar starts at the top safe area, so it never meets the screen corner curve. The first segment grows out of the edge in a curve of `size.timelineCap`.
- The bar ends at the top of the mini player pill. No strip runs beside the pill or along the display corner.
- The scrub label has two lines: the movement, then the time. It follows the finger but stays whole on screen.
- Over a picture with Increase Contrast, each segment gets a 2 pt keyline in the page colour.

## Mini player

- A pill in the tab bar row, on the side of the timeline: a round play/pause button and the square cover at the screen edge. It shows no text: the scrub label and the player name what plays.
- A tap on the cover opens the player. A tap on play/pause stays on the page.
- The native tab bar gets narrower to make room. The pill has the top, bottom and height of the tab capsule, and system glass.
- The square cover keeps an even gap from the display bend, on either edge. The display corner geometry places only the cover.
- When nothing plays, the pill and the timeline go away.

## Player colour

The colour rules of the cover room, the hall and the temporary Player Tint slider are in [tokens.md](tokens.md).
