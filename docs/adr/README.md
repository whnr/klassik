# Architecture decision records

A record holds one decision that a code comment or a commit body cannot hold. Each file has Context, Decision and Consequences. A new record gets the next free number. Numbers are never used again or changed.

## The bar for a new record

Write a record only when the decision meets all three conditions:

1. It is hard to reverse.
2. It is surprising without context.
3. It is a real trade-off with a named alternative.

Everything else goes elsewhere:

- Terms go to [`CONTEXT.md`](../../CONTEXT.md).
- Layout, visual and interaction rules are the specimen pages. A rule that a page cannot show is a short comment in that page's HTML, such as [`design/specimen/player.html`](../../design/specimen/player.html).
- The reason for a code choice goes into a short comment at that code.
- Everything else goes into the commit message or the bead.

A human reviews every record. An agent writes a qualifying record as Proposed and lists it on Flo's desk. It becomes Accepted only after Flo reviews it. An agent never records its own choice as decided.

## When a decision changes

- A changed decision gets a new record. Its header line names the record and the rules that it replaces: "Replaces the offline rules of [0013](0013-favourites.md)."
- The old record keeps its text. Its header line gets one sentence that points to the new record.
- The index row of the old record names the new record: "(partly replaced by 0052)".
- Flo can annul a record instead of replacing it, and so revive the record that it replaced. Its header line says "Annulled by Flo on <date>", gives his reason and names the record that stands again.
- Edit a record in place only for a fix that changes no decision, such as a typo or a wrong link.

## Index

| No.                                                     | Decision                                                                         | Date       |
| ------------------------------------------------------- | -------------------------------------------------------------------------------- | ---------- |
| [0001](0001-work-first.md)                              | The work is the primary object                                                   | 2026-10-17 |
| [0002](0002-library-sync.md)                            | Sync the whole library into a local cache                                        | 2026-10-17 |
| [0003](0003-classical-filter.md)                        | Classical filter: rules joined by OR, conditions joined by AND                   | 2026-10-17 |
| [0004](0004-work-grouping.md)                           | How tracks group into works and recordings                                       | 2026-10-17 |
| [0005](0005-gapless-playback.md)                        | Gapless playback with AVAudioEngine and the MP3 header (partly replaced by 0060) | 2026-10-17 |
| [0011](0011-enrichment.md)                              | Composition dates from MusicBrainz and Wikidata (partly replaced by 0042)        | 2026-10-19 |
| [0013](0013-favourites.md)                              | Favourites and the recording order (partly replaced by 0052)                     | 2026-10-31 |
| [0021](0021-design-tokens.md)                           | Design tokens in the repository                                                  | 2026-11-05 |
| [0042](0042-wikidata-pass-in-the-background.md)         | A background pass loads Wikidata for the whole library                           | 2026-11-14 |
| [0051](0051-pictures-and-album-art-in-local-storage.md) | Pictures and album art in Local Storage (partly replaced by 0059; extended by 0060) | 2026-11-17 |
| [0052](0052-favourites-stay-in-the-app.md)              | Favourites stay in the app                                                       | 2026-11-18 |
| [0059](0059-covers-and-pictures-before-pages.md)        | Fetch covers and pictures before pages need them                                 | 2026-11-18 |
| [0060](0060-early-playback-and-read-ahead.md)           | Start playback early and read ahead quietly (partly replaces 0005; extends 0051) | 2026-11-18 |
