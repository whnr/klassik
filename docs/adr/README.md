# Architecture decision records

One file for each decision that a code comment or a commit body cannot hold. Each file has Context, Decision and Consequences. A new decision gets the next number. A changed decision gets a new record that names the record it replaces.

| No. | Decision | Date |
| --- | --- | --- |
| [0001](0001-work-first.md) | The work is the primary object | 2026-10-17 |
| [0002](0002-library-sync.md) | Sync the whole library into a local cache | 2026-10-17 |
| [0003](0003-classical-filter.md) | Classical filter: rules joined by OR, conditions joined by AND | 2026-10-17 |
| [0004](0004-work-grouping.md) | How tracks group into works and recordings | 2026-10-17 |
| [0005](0005-gapless-playback.md) | Gapless playback with AVAudioEngine and the MP3 header | 2026-10-17 |
| [0006](0006-queue.md) | The queue holds recordings | 2026-10-18 |
| [0007](0007-replaygain.md) | ReplayGain in album mode | 2026-10-18 |
| [0008](0008-offline-storage.md) | Downloads and the cache | 2026-10-18 |
| [0009](0009-reference-recording.md) | The reference recording is a star (replaced by 0013) | 2026-10-18 |
| [0010](0010-incremental-sync.md) | Sync at start only when the server changed | 2026-10-18 |
| [0011](0011-enrichment.md) | Composition dates from MusicBrainz and Wikidata (timeline rules replaced by 0016) | 2026-10-19 |
| [0012](0012-composer-lists.md) | Look up works composer by composer | 2026-10-19 |
| [0013](0013-favourites.md) | Favourites and the recording order | 2026-10-31 |
| [0014](0014-player.md) | The player: rows beside one timeline (partly replaced by 0015) | 2026-11-02 |
| [0015](0015-player-page.md) | The player is the page of what plays | 2026-11-03 |
| [0016](0016-chronology.md) | The Chronology: a chart of one composer among their contemporaries | 2026-11-04 |
| [0017](0017-composer-and-performer-pages.md) | Composer and performer pages | 2026-11-04 |
| [0018](0018-stack-and-back.md) | The system back stack, with the name of the page behind | 2026-11-04 |
