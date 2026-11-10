# Architecture decision records

One file for each decision that a code comment or a commit body cannot hold. Each file has Context, Decision and Consequences. A new decision gets the next number.

## When a decision changes

- A changed decision gets a new record. Its header line names the record and the rules that it replaces: "Replaces the row rules of [0014](0014-player.md)."
- The old record keeps its text. Its header line gets one sentence that points to the new record: "Replaced by [0013](0013-favourites.md)." or "The row rules are replaced by [0027](0027-player-rows.md)."
- The index row of the old record names the new record: "(replaced by 0013)" or "(partly replaced by 0015 and 0027)".
- Edit a record in place only for a fix that changes no decision, such as a typo or a wrong link. A refinement in the same design round, before Flo has tested the next build, is such a fix.

| No. | Decision | Date |
| --- | --- | --- |
| [0001](0001-work-first.md) | The work is the primary object | 2026-10-17 |
| [0002](0002-library-sync.md) | Sync the whole library into a local cache | 2026-10-17 |
| [0003](0003-classical-filter.md) | Classical filter: rules joined by OR, conditions joined by AND | 2026-10-17 |
| [0004](0004-work-grouping.md) | How tracks group into works and recordings | 2026-10-17 |
| [0005](0005-gapless-playback.md) | Gapless playback with AVAudioEngine and the MP3 header | 2026-10-17 |
| [0006](0006-queue.md) | The queue holds recordings (partly replaced by 0013) | 2026-10-18 |
| [0007](0007-replaygain.md) | ReplayGain in album mode | 2026-10-18 |
| [0008](0008-offline-storage.md) | Downloads and the cache | 2026-10-18 |
| [0009](0009-reference-recording.md) | The reference recording is a star (replaced by 0013) | 2026-10-18 |
| [0010](0010-incremental-sync.md) | Sync at start only when the server changed | 2026-10-18 |
| [0011](0011-enrichment.md) | Composition dates from MusicBrainz and Wikidata (partly replaced by 0012 and 0016) | 2026-10-19 |
| [0012](0012-composer-lists.md) | Look up works composer by composer | 2026-10-19 |
| [0013](0013-favourites.md) | Favourites and the recording order | 2026-10-31 |
| [0014](0014-player.md) | The player: rows beside one timeline (partly replaced by 0015, 0027 and 0028) | 2026-11-02 |
| [0015](0015-player-page.md) | The player is the page of what plays (partly replaced by 0028) | 2026-11-03 |
| [0016](0016-chronology.md) | The Chronology: a chart of one composer among their contemporaries (partly replaced by 0022 and 0026) | 2026-11-04 |
| [0017](0017-composer-and-performer-pages.md) | Composer and performer pages (partly replaced by 0020 and 0032) | 2026-11-04 |
| [0018](0018-stack-and-back.md) | The system back stack, with the name of the page behind (partly replaced by 0029) | 2026-11-04 |
| [0019](0019-performer-facts.md) | Performer facts from Wikidata | 2026-11-04 |
| [0020](0020-set-and-condition.md) | Set means works; a search row is a condition | 2026-11-04 |
| [0021](0021-design-tokens.md) | Design tokens in the repository | 2026-11-05 |
| [0022](0022-chronology-taps.md) | Chronology taps open pages | 2026-11-07 |
| [0023](0023-no-title-in-the-bar.md) | No title in the navigation bar | 2026-11-07 |
| [0024](0024-album-work-headings.md) | Work headings on an album page only for whole works | 2026-11-07 |
| [0025](0025-search-field-and-filter-sheet.md) | The search field finds; filters open in a sheet (partly replaced by 0029) | 2026-11-07 |
| [0026](0026-contemporaries-by-active-years.md) | Contemporaries by overlapping active years | 2026-11-07 |
| [0027](0027-player-rows.md) | Player rows: play at the end, open only what differs | 2026-11-08 |
| [0028](0028-mini-player-pill.md) | The mini player is a pill at the end of the timeline | 2026-11-08 |
| [0029](0029-search-at-the-top.md) | Search at the top, with a back arrow and recent searches | 2026-11-08 |
| [0030](0030-type-and-spacing.md) | Type and spacing from one ratio | 2026-11-08 |
| [0031](0031-no-separator-glyph.md) | No separator glyph: prose, words and role lines | 2026-11-09 |
| [0032](0032-fermata-mark.md) | The fermata: one solid drawing, grey when not set (partly replaced by 0033) | 2026-11-08 |
| [0033](0033-engraved-fermata.md) | The engraved fermata, strong when set and quiet when not | 2026-11-09 |
| [0034](0034-colour.md) | Colour: a programme by day, the hall at night (the dark timeline partly replaced by 0035) | 2026-11-09 |
| [0035](0035-timeline-shape.md) | The timeline: flush, round on the content side, a gap for each movement | 2026-11-10 |
