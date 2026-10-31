# Work and composer facts in OpenSubsonic fields

Bead: sz-rs30.1.74.1. Checked 2026-10-31 on Navidrome 0.64.2 (linux amd64, started as in `scripts/fixture-server.sh`). Probe: `probe.py` in this folder. It writes sine tones only. Tag names come from sz-rs30.2 (DESIGN, tag contract).

## Answer

No. A composition date in the tags does not reach the client. The OpenSubsonic spec has no field for it. Navidrome 0.64.2 does not serve it.

- `Work` has two fields: `name` and `musicBrainzId`. `Movement` has `name`, `number`, `count`. None has a date. (Spec: Work, Movement pages.)
- Navidrome reads `TXXX:COMPOSITIONDATE` and drops it (proven: no served field changed). It drops `COMPOSED` and `WORKDATE` too. `mappings.yaml` has no such tag.
- `COMM` reaches `Child.comment` as free text. A date there arrives as a string such as "composed 1884-1885". The client must parse it. Proven.
- ADR 0011 stays true for the API: a work date must come from MusicBrainz and Wikidata.
- The work ID does arrive: `works[].musicBrainzId` (proven). ADR 0011 can rely on it.

One date path comes near: `TDOR` (ORIGINALDATE). It reaches `AlbumID3.originalReleaseDate` and, in one case, the song `year`. Its meaning is "first release of the album". It holds one value per album, not per work. Using it for a composition year abuses the tag. Not recommended.

## Date tags (proven)

| Tag (MP3 / FLAC) | OpenSubsonic field |
| --- | --- |
| TDRC / DATE | `Child.year` (recording year), `AlbumID3.releaseDate` in the legacy case below |
| TDRL / RELEASEDATE | `AlbumID3.releaseDate` (ItemDate: year, month, day) |
| TDOR / ORIGINALDATE | `AlbumID3.originalReleaseDate`; may also set `year` (below) |
| TXXX:COMPOSITIONDATE, COMPOSED, WORKDATE | not served |
| COMM / COMMENT | `Child.comment` (free text) |
| TIT3 | appended to `Child.title`, as "Title (subtitle 1881)" |

`year` rule. Source: Navidrome `model/metadata/map_mediafile.go`, `mapDates`. Proven with 12 probe files. If TDOR is set, TDRL is empty and TDRC is not older than TDOR, then `year` is the TDOR year and `releaseDate` is the TDRC value. Else `year` is the TDRC year. The sz-rs30.2 contract writes TDRC and TDRL and no TDOR. So `year` is the recording year, as the recordings list needs.

## Tag to field table (proven)

| Tag (sz-rs30.2) | OpenSubsonic field | Note |
| --- | --- | --- |
| WORK (TIT1, TXXX:WORK) | `Child.works[].name` | Spec: Work |
| MusicBrainz Work Id | `Child.works[].musicBrainzId` | Only with a WORK tag |
| MOVEMENTNAME (MVNM) | `Child.movements[].name` | |
| MOVEMENT (TXXX) | `Child.movements[].number` | |
| MOVEMENTTOTAL (TXXX) | `Child.movements[].count` | |
| COMPOSER (TCOM) | `Child.contributors[]` role `composer`; `Child.displayComposer` | Also an `ArtistID3` with `roles: ["composer"]`, `albumCount: 0` |
| Composer sort (TSOC) | not served | Composer `sortName` is the lowercased name |
| Artist sort (TSOP, TSO2), title sort (TSOT) | not served | `sortName` is the lowercased name or title |
| ARRANGER (TIPL arranger) | `contributors[]` role `arranger` | |
| CONDUCTOR (TPE3) | `contributors[]` role `conductor` | |
| PERFORMER (TMCL) | `contributors[]` role `performer`, `subRole` title-cased ("Violin", "Orchestra") | |
| ARTIST, ALBUMARTIST | `artists[]`, `albumArtists[]`, `displayArtist`, `displayAlbumArtist` | |
| GROUPING (GRP1) | `Child.groupings[]` | |
| GENRE (three values) | `Child.genres[]`; `Child.genre` holds the first value only | |

The spec page does not list the `role` values. Navidrome sent `composer`, `conductor`, `arranger`, `performer`.

## Other fields for the Chronology

- Composer name and ID: `contributors[role=composer]`, `displayComposer`. The composer `ArtistID3` has `id`, `name`, `sortName`, `musicBrainzId` (empty in the probe), `roles`.
- Composer life dates: no field. `getArtistInfo2` returned a `biography` text. Navidrome fetched it from an outside agent. It is prose, and it depends on the server setup. Not a stable source.
- Movements of a work: `movements[].number` and `count`.
- Era hint: `genres[]`. The sz-rs30.2 contract writes the period as the third genre. That is Flo's convention, not a standard. Other libraries have no period.
- Year hint without a work date: `year` and `AlbumID3.releaseDate`. They are upper bounds for a work date, not the date.

## What reaches the client without these tags (proven)

| Library has | Client gets |
| --- | --- |
| Title, artist, album only | Those three. `works`, `movements`, `contributors`, `displayComposer`, `genres` are empty. No `year`. |
| Plus COMPOSER, GENRE=Classical, DATE | Plus `contributors[composer]`, `displayComposer`, `genres`, `year`. `works` and `movements` stay empty. |
| Plus MusicBrainz Work Id, no WORK | `works` stays empty. The ID alone is lost. |
| FLAC with the same Vorbis names | Same result as MP3. |

A weak library still gets a composer name. The app must then read the work and the movement from the title.

## Unproven

- The composer MBID tag (`MusicBrainz Composer Id`) reaching `ArtistID3.musicBrainzId`: read in `mappings.yaml`, not run.
- M4A atoms: not run here. sz-rs30.2 DESIGN records a probe on 0.64.2.
- Servers other than Navidrome 0.64.2.
- Why sort tags do not become `sortName`: observed, cause not read in the source.
- Navidrome custom tags (`ND_TAGS`): not tested. They are not standard.
- The spec pages were read through a summarising fetch, not the raw OpenAPI file.

## Sources

- OpenSubsonic response pages: Child, AlbumID3, ArtistID3, Work, Movement, Contributor (https://opensubsonic.netlify.app/docs/responses/).
- Navidrome v0.64.2 `resources/mappings.yaml` and `model/metadata/map_mediafile.go` (github.com/navidrome/navidrome).
- Probe on Navidrome 0.64.2: `getSong` (via `search3`), `getAlbumList2`, `search3`, `getArtist`, `getArtistInfo2`, `getGenres`.
