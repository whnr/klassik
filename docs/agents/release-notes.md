# Release notes

A release makes two short texts. Neither lists every commit.

## 1. TestFlight "What to Test"

File: `docs/what-to-test.md`. A feature summary that any tester can read.

- First line `Klassik X.Y.Z`, then one `- ` bullet per real change.
- Up to about 20 words a bullet (hard limit 25), about 100 words in total (hard limit 150).
- Say what the tester sees. No bead ids, no development terms.
- `scripts/testflight_notes.py --check` enforces the format.

Example (0.20.0):

```
Klassik 0.20.0

- Music starts at once, even for tracks you have never played, on Wi-Fi and on cellular.
- Every tinted name on a recording, album, person page and the player opens its page.
- Person and player pages follow the new design; grid covers line up.
- The player no longer flashes when you scrub; the lock screen shows the cover.
- Search shows Composers, Performers, Works and Albums. "Eroica" finds the work.
- Swipe down closes the player, Filters and the Chronology works sheet.
- Settings are regrouped; Technical Details sits under Advanced.
```

## 2. The owner's tester list

One comment on the release PR that mentions `@whnr`.

- Group by feature. Give each feature 1 to 5 checks, by how complex it is.
- Write each check as what the owner does and what he expects to see. Never one check per commit.
- Known issues: one line each, with the release that fixes them.
- End with: reply here with what does not match your expectations.

Example (0.20.0):

```
@whnr 0.20.0 tester list:

**Instant play**
1. Play a work you have never played, on Wi-Fi. Expect sound at once and smooth skips within the work.
2. Repeat on cellular, then with Low Data Mode on. Expect only the next track to load ahead.
3. Stop the server while music plays. Expect a pause and one quiet status in Library, no notices.

**Links**
1. On a recording, an album, a person page and the player, tap each tinted name. Expect its page.
2. Tap a name in the player. Expect the player to close and the page to open.

**Search**
1. Search a composer. Expect Composers, Performers, Works, Albums. Albums lists only albums.
2. Search "Eroica". Expect the Beethoven work under Works with a "Track:" line.

**Player**
1. Scrub across a movement boundary. Expect no flash.
2. Lock the phone and skip a movement. Expect the cover on the lock screen, without flicker.

**Sheets and Settings**
1. Swipe down on the player, Filters and the Chronology works sheet. Expect each to close.
2. Open Settings. Expect Playback, Library, Colour, Advanced; Technical Details under Advanced.

Known: after a search while music plays, the Chronology label can be cut off. Fixed in 0.20.1.

Reply here with what does not match your expectations.
```
