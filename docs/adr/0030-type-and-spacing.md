# 0030. Type and spacing from one ratio

Date: 2026-11-08. Decided by Flo after specimen rounds 10 to 14 on the phone. Beads: sz-rs30.1.83.5, sz-rs30.1.83.15.

## Context

The specimen in neutral iOS styles had a weak hierarchy and no character. The work page read like a settings list. Small grey labels carried the facts that tell recordings apart. Flo compared 18 display faces and 10 text faces on a type sheet, then judged the baseline on the real pages.

## Decision

- **Faces.** Wittgenstein at weight 500 sets page titles and section headings only. SF sets everything else. Wittgenstein is bundled under the SIL Open Font License 1.1, which fits Apache-2.0. System chrome stays SF.
- **One ratio.** Body is 17 pt. Every size is 17 pt times 4:3 to the power of its step. The page title is step 2 (30.2 pt). The section heading is step 1 (22.7 pt). Values stay fractional.
- **Spacing roles.** The same ratio sets three gaps: inside a group (step −4, 5.4 pt), between groups (step 1, 22.7 pt), between sections (step 3, 40.3 pt). A row takes half the gap between groups above and half below. System insets and the 44 pt hit target stay as iOS sets them.
- **Dynamic Type.** A custom size scales through the metrics of its text style (`Font.custom(_:size:relativeTo:)`, `ScaledMetric`), as ADR 0021 says. Text is never capped at large sizes.
- **Figures** are lining and proportional everywhere, durations included.
- **Lists.** Content pages (work, player, album, person) use plain lists. Settings and sheets keep inset grouped lists. Section headers are sentence case.
- **Recording rows** lead with the principal performers and the year. The other names follow, all of them. Album and duration form the quiet facts line, at the size of the performers.
- **Numbers** never wrap away from their word or catalogue prefix: a no-break space in "11 movements", "Op. 61", "No. 1", "BWV 1050". One movement is "1 movement".
- The playing row has no bold title. The bar and the open row mark it.
- No italic nickname. No tag field holds a nickname apart: Navidrome appends TIT3 to the title.

## Consequences

- The app bundles one font file and its licence text.
- Two sans faces never mix: SF is the only text face.
- The fermata becomes a custom SF Symbol. Its drawing is open on the design map.
- The middle dot as a separator is open: sz-rs30.1.83.16.
- A line that names the album must say that it is the album. Where this applies is open on the design map.
