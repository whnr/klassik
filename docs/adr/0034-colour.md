# 0034. Colour: a programme by day, the hall at night

Date: 2026-11-09. Decided by Flo after specimen rounds 19 to 24 on the phone. Beads: the colour map sz-rs30.1.83.19 and its tickets .1 to .16.

## Context

The specimen used neutral iOS colours and system blue. Klassik needs its own voice: a concert programme, elegant and structured, with the warmth of classical music. Colour must also stay readable for every listener, on any cover and any picture. Research (sz-rs30.1.83.19.14) set the method: design in OKLCH, lightness first, and check WCAG from the final hex.

## Decision

- **Two rooms.** Light is a sunlit room with the programme in front of you. Dark is the concert hall with the lights down, never a bright booklet in a dark room. One family of hues serves both rooms.
- **Paper and hall.** The light page is middle paper, `#faf3e5` (OKLCH 0.966 0.020 85), never white. The dark page is a warm near-black at L 0.18, tinted toward the accent, never black. Neutrals carry a trace of the accent hue.
- **Accent families.** Claret (hue 6), bottle green (hue 160) and plum (hue 345) stay as an in-app switch. Claret is the default. The grilling sz-rs30.1.83.19.15 decides before 1.0 whether one family wins. Oxblood, bronze, gold and blue are out.
- **Where colour goes.** The accent marks taps and live state: links, controls, the playing row, the played timeline, the set fermata. Headings stay ink. System chrome (tab bar, sheets, glass, the mini player pill) stays Apple's.
- **Solved values.** Each colour has a contrast target on its ground. A script solves the lightness for that target, then lowers chroma until the colour fits sRGB. The token file keeps the hex value, with the OKLCH source beside it.
- **Targets, standard modes (WCAG 2.2 AA).** Night text 11.5:1. Secondary text 5.2:1 by day and 6:1 at night. Tint 7:1 by day and 6.5:1 at night. Marks and large text 3:1. Tertiary text is for disabled items only. Placeholders use secondary text.
- **Targets, Increase Contrast (AAA).** Text and links reach 7:1 on every ground: page, row, grouped and elevated. Marks reach 4.5:1 on every ground. On the page, secondary text keeps 7.5:1 by day and 8:1 at night, and the tint keeps 9:1.
- **Fills.** The accent fill is the deep jewel behind a light label. Standard and quiet fills are translucent overlays, so the Chronology lines stay visible through its era bands. In the hall with Increase Contrast, a filled control gets a 1 pt ring in the tint, because the fill stands only 1.6:1 from the page.
- **Links.** Names and links take the accent colour with no underline. Increase Contrast adds the standard underline in the link's own colour.
- **Favourite.** As [0033](0033-engraved-fermata.md) says: the accent at its strongest chroma when set, a quiet grey at 3:1 when not set.
- **Swipe actions.** Four hues with a white icon and label: Play Next violet (hue 285), Add to Queue amber (hue 60), Download teal (hue 215), Favourite in the accent family. Add to Queue and Favourite sit OKLab L 0.12 darker, so the pair on each edge differs for colour-blind eyes. The step belongs to the action, not to the edge. Labels reach 4.6:1, 7:1 with Increase Contrast.
- **Timeline.** The played part takes the tint. It stands 4.5:1 apart from the unplayed part. The unplayed part is a quiet track, below 3:1 on the page. Both targets on the played part leave no room for more.
- **Player looks.** The cover room is the default player. While the player plays, its ground takes the cover's hue: light L 0.935 and chroma up to 0.026, dark L 0.235 and chroma up to 0.04, light with Increase Contrast L 0.95 and chroma up to 0.018. Secondary text, the tint and the favourite are solved again on that ground. The played timeline and the playing row bar take a mark colour from the cover, at 3:1 (4.5:1 with Increase Contrast, also against the unplayed part). Controls keep the accent. The hall is a setting beside it: the player in the dark room, a step darker, lit by a glow in the cover's hue.
- **Cover hue.** The app finds the heaviest chromatic hue family in a small copy of the cover, never the average. A grey cover takes the accent. Detail: `docs/research/cover-colour.md` on branch `research/cover-colour`.
- **Text over pictures.** On a person picture, the name and the facts line sit in paper colour over a blur and a hall scrim. The app measures the blurred picture under the text and sets the scrim just strong enough: 4.5:1 for the facts and 3:1 for the name (7:1 and 4.5:1 with Increase Contrast). The minimum is 25%. A picture that cannot be read gets 90%.
- **Chronology.** The playing composer takes the accent. The focus and the last opened composer take ink.

## Consequences

- The token files hold the four themes of each accent family in `design/accent-*.tokens.json`. The theme files point each colour there. `scripts/tokens.py` writes the default family plainly and the others under `data-accent`.
- The UI tracer (sz-4k87) generates the colour sets for each family and moves the app off system colours. It renames the swipe action Reference to Favourite.
- The cover room, the cover hue and the picture scrim are runtime rules, not tokens. The tracer builds them in Core Image with the same targets.
- Open question: in the locked standard values, some marks sit below 3:1 on rows, grouped lists and grey covers. Bead sz-rs30.1.83.19.17 asks Flo to keep or fix them.
