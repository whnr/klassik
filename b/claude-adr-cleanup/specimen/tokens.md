# Type, words, layout and colour

Rules behind `tokens.html`, the token files and `design/scripts/palette.py`. The values live in the token files and in `palette.py`. This note gives the rules that the values cannot show.

## Type

- Wittgenstein at weight 500 sets page titles and section headings only. SF sets everything else, and system chrome stays SF. Two sans faces never mix.
- One ratio: body is 17 pt, and every size is 17 pt × (4:3)^step. Page title is step 2, section heading step 1. Values stay fractional.
- The same ratio sets three gaps: inside a group (step −4), between groups (step 1), between sections (step 3). A row takes half the gap between groups above and half below. System insets and the 44 pt hit target stay as iOS sets them.
- A custom size scales through the metrics of its text style. Text is never capped at large sizes.
- Figures are lining and proportional everywhere, durations included.
- No italic nickname: no tag field holds a nickname apart, because Navidrome appends TIT3 to the title.

## Words

- No separator glyph: no middle dot, pipe, slash or spaced dash between facts. A dot says nothing about how two facts relate.
- Facts are prose: "Recorded in 1972 on Dvořák Symphonies. 42 minutes, 4 movements." The player header has the same line without the album.
- Durations in prose round to the nearest minute, never under one: "1 hour 48 minutes". The timeline and the rows keep exact times.
- Counts are words. The noun follows the place: movements in a work or recording, tracks on an album, works for a composer, recordings for a performer. A person in search gets one count for each role, the biggest first.
- A section heading takes its count in parentheses, a step lighter: "Recordings (23)".
- Short facts join with a comma: "Czech composer, 1841–1904".
- A number never wraps away from its word or prefix: a no-break space in "11 movements", "Op. 61", "BWV 1050". One movement is "1 movement".
- Names stand one line per role, behind a small-cap label: "conductor Rafael Kubelík". The header centres the lines; a row aligns them on the leading edge. Names never line up in a label column.
- The label is lowercase text in true small caps, at the size of the names, tracked +0.06 em, in secondary colour, tied to the first name by a no-break space of about 0.45 em. At accessibility sizes the label stands above its names.
- Names in one role join with commas and "and". When a name holds a comma ("Kubelík, Rafael"), each name takes its own line with the label repeated. Names without a role go last, unlabelled.
- Free role tags show as tagged. Klassik does not translate or pluralise them.
- Recording rows lead with the principal performers and the year. All other names follow. Album and duration form the quiet facts line.

## Lists and margins

- Content pages (work, player, album, person) use plain lists on the page ground, with no cards. Settings and sheets use inset grouped lists. The Chronology works drawer uses plain work rows on the page ground at every detent, because it shows library content.
- Section headers are sentence case.
- A hairline runs only between two list items. No hairline around headings, subtitles, covers, playback capsules or section boundaries.
- With the timeline on the right, a content page has `space-l` on the left and `space-l` plus the timeline width on the right. On the left edge the sides swap. Without a timeline, both sides get `space-l` plus half the timeline width. So the content keeps its width when playback starts or ends. The scroll indicator does not count; it runs beside the timeline.
- Settings and sheets keep the system insets.
- Titles on pages without a picture sit below the system top blur, with the large top gap.

## Colour

- Two rooms. Light is a sunlit room with the programme in front of you: middle paper, never white. Dark is the concert hall with the lights down: a warm near-black tinted toward the accent, never black. Neutrals carry a trace of the accent hue.
- Accent families claret (default), bottle green and plum are an in-app switch.
- The accent marks taps and live state: links, controls, the playing row, the played timeline, the set fermata. Headings stay ink. System chrome (tab bar, sheets, glass, the pill) stays Apple's.
- Each colour has a contrast target on its ground. `palette.py` solves the lightness for that target, then lowers chroma until the colour fits sRGB. Design in OKLCH, lightness first; check WCAG from the final hex.
- Standard targets follow WCAG 2.2 AA; Increase Contrast follows AAA on every ground. `palette.py` holds the numbers, and `check.py` proves every pair. Tertiary text is for disabled items only; placeholders use secondary text.
- Standard and quiet fills are translucent, so the Chronology lines stay visible through the era bands. In the hall with Increase Contrast, a filled control gets a 1 pt ring in the tint.
- Links take the accent with no underline. Increase Contrast adds the standard underline.
- Swipe actions: Play Next violet, Add to Queue amber, Download teal, Favourite in the accent family, with a white icon and label. Add to Queue and Favourite sit darker, so the pair on each edge differs for colour-blind eyes.
- Timeline: the played part takes the tint. The unplayed part is a quiet track. In the dark room it is lighter, a mix of text into the page of about 2:1, an exception for the timeline only.
- The unset fermata reaches 3:1 on every ground (4.5:1 with Increase Contrast). The set and unset states differ in lightness, so Differentiate Without Color changes nothing. The VoiceOver label carries the state.
- A named picture that has not loaded shows the opaque elevated ground.

## Player colour

- The cover room is the default player. While the player plays, its ground takes the hue of the cover. Secondary text, the tint and the favourite are solved again on that ground. The played timeline and the playing row bar take a mark colour from the cover. Controls keep the accent.
- The hall is a setting beside it: the player in the dark room, a step darker, lit by a glow in the cover's hue.
- The cover hue is the heaviest chromatic hue family in a small copy of the cover, never the average. A grey cover takes the accent.
- Player Tint is a temporary slider from 0 to 5 in 0.5 steps, default 3. It multiplies the cover chroma and lowers lightness a little, so gamut mapping keeps the steps distinct. The fade keeps its height and stops, and text keeps its targets. The control goes when Flo picks a strength.
- Text over a person picture is paper colour over a blur and a scrim. The app measures the blurred picture under the text and sets the scrim just strong enough for the targets, at least 25%. A picture that cannot be read gets 90%. The scrim protects both favourite states.
- The cover room, the cover hue and the scrim are runtime rules, not tokens.

## Checks

The checks cannot judge looks or Safari. Flo's phone stays the judge for both.
