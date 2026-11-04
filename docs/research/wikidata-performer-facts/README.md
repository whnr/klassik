# What Wikidata gives a performer page

Bead: sz-rs30.1.74.13. Checked 2026-11-04 against the live APIs from Linux. Probe: `probe.py` in this folder (566 requests). It downloads no image and reads no library. The names are public, well-known classical performers, typed as weak tags spell them. Method as in `../wikidata-composer-facts/`.

## Answer

Wikidata finds the right conductor, soloist, singer or ensemble from a name alone. It gives a description, dates and, in most cases, a picture. ADR 0017 holds, with four risks (section "Risks for ADR 0017").

- Match: full-text search with `haswbstatement:P434` (the item has a MusicBrainz artist ID). First hit right for 94 of 94 tag variants: 58 of persons, 36 of ensembles. No wrong first hit.
- Dates: persons have P569 in 52 of 52. Ensembles have P571 (inception) in 33 of 33, and P576 (dissolved) in 2.
- Description: English and German for 52 of 52 persons, 33 and 31 of 33 ensembles.
- Picture: P18 for 50 of 52 persons and 26 of 33 ensembles. 44 of 50 person files and 21 of 26 ensemble files need a credit line.
- Album-wide strings: the app must split them itself. Navidrome leaves 18 of 24 sample strings whole.

## Sample

85 Wikidata items, each checked by its English label: 21 conductors, 21 instrumental soloists, 10 singers, 19 orchestras, 8 choirs, 6 chamber ensembles. 94 tag variants: full names, surname only, "Surname, Given", "Sir", missing accents and hyphens, German and Dutch ensemble names. Plus 3 ambiguous surnames, 9 junk tags and 24 album-wide strings.

## Match from a name

| Way | Request | Persons (58) right / wrong / none | Ensembles (36) |
| --- | --- | --- | --- |
| A. `wbsearchentities`, first hit | 1 | 51 / 7 / 0 | 36 / 0 / 0 |
| B. `list=search`, no filter | 1 | 51 / 7 / 0 | 36 / 0 / 0 |
| C. `list=search` with `haswbstatement:P106=…\|P31=…` (9 occupations, 6 ensemble classes) | 1 | 56 / 2 / 0 | 28 / 1 / 7 |
| D. `list=search` with `haswbstatement:P434` | 1 | 58 / 0 / 0 | 36 / 0 / 0 |

Use D: `action=query&list=search&srsearch=<name> haswbstatement:P434`.

- A and B fail on surname tags: "Abbado", "Bernstein", "Harnoncourt", "Argerich", "Callas", "Fischer-Dieskau", "Pavarotti" return a family name item or a namesake.
- C fails because occupations and classes differ from item to item. `haswbstatement` reads direct statements only, not subclasses. Lang Lang has only occupation Q61996187, not pianist Q486748, so C returns István Láng. The 33 ensembles use 19 different P31 values: symphony orchestra, baroque orchestra, boys' choir, radio choir, piano trio and more. 7 ensembles fall outside the list.
- D works on this sample because P434 was on 85 of 85 items. It also drops the family name items. Discogs P1953 also was on 85 of 85. The app reads no MusicBrainz ID from tags. The filter only narrows the Wikidata search. Flo must decide if this counts as a dependency on MusicBrainz.
- `haswbstatement` takes `|` for OR, and two `haswbstatement` terms join with AND. Proven live.

Surname tags that name two performers (way D):

| Tag | D first hits | With the role filter `haswbstatement:P106=Q158852` (conductor) or `Q486748` (pianist) |
| --- | --- | --- |
| Kleiber | Carlos, Erich | Carlos, Erich |
| Petrenko | Aleksei (actor), Mykhailo (poet), Kirill | Kirill, Vasily |
| Gould | Elliott (actor), Glenn | Glenn (pianist), Morton |
| Davis | not run | Andrew, Colin (conductor) |

A contributor role from OpenSubsonic (`contributors[].role`, for example "conductor") maps to a P106 filter and removes the actors. It does not decide between two conductors.

Auto-accept rule tested: accept the first hit when one of its labels or aliases, in any language, has the same words as the tag (case, accents and "Sir" ignored). It accepted 94 of 94 first hits, all right. It is not safe for one word: "Gould" equals an alias of Elliott Gould, and "Anonymous" equals the label of the hacker group.

Junk tags with way D: "Various Artists", "Unknown Artist", "[unknown]" and "Traditional" return special-purpose items (P31 Q59755569). "Anonymous" returns the hacker group. "Orchestra", "Soloists", "Chor" and "Ensemble" return a random ensemble. The app needs a stop list and must drop items with P31 Q59755569.

## Album-wide artist strings

- OpenSubsonic gives `artists[]`, `albumArtists[]` and `contributors[]` (https://opensubsonic.netlify.app/docs/responses/child/). A server fills them from multi-valued tags.
- Navidrome 0.64.2 splits one ARTIST or ALBUMARTIST value only on `" / "`, `" feat. "`, `" feat "`, `" ft. "`, `" ft "` and `"; "` (`resources/mappings.yaml`, https://github.com/navidrome/navidrome/blob/v0.64.2/resources/mappings.yaml). A comma, `&` or "and" stays inside one artist.
- A search for the whole string finds one of the performers for 3 of 24. "Berliner Philharmoniker, Herbert von Karajan" returns the Karajan Academy. Never search an unsplit string without a check.

| Split | Strings exactly right (24) | Performers found (53) |
| --- | --- | --- |
| Navidrome separators only | 6 | 14 |
| Also on `,` `&` ` and ` | 22 | 51 |
| As above, and rejoin "Surname, Given" (one word, then up to 3 words with no ensemble word) | 23 | 51 |

- The one failure: "Chor und Symphonieorchester des Bayerischen Rundfunks" names two ensembles that share one ending. No split rule gives both.
- "Orchestre Révolutionnaire et Romantique" and "Academy of St Martin in the Fields" survive, because the split does not use "et" or "in".
- Keep-or-split: apply the token rule to the hit of the whole string. It kept "Beaux Arts Trio" and rejected the 5 wrong whole-string hits.
- The rejoin rule is untested on a surname list such as "Argerich, Abbado". It would join them into one name.

## Dates and description

- Persons: P569 52 of 52. P570 for the 21 dead performers. Show the years, as for composers.
- Ensembles: no P569. P571 inception 33 of 33 ("1882"). P576 dissolved for 2 (Alban Berg Quartett, Beaux Arts Trio). Show "founded 1882", or "1955–2008".
- Description languages, persons (52): en 52, de 52, fr 52, nl 52, es 50, it 49. Ensembles (33): en 33, de 31, nl 29, fr 28, es 23, it 11.
- 33 of 52 English person descriptions hold years, in many forms: "(1933–2014)", "(born 1955)", "(1941-)", "born 2 October 1944". German uses "(* 1941)" and "(geb. 1966)". Only 2 of 33 ensemble descriptions hold a year.
- Description years can be wrong: Pavarotti says "(1935–2006)", P570 says 2007. Take the years from P569 and P570, not from the text.
- Some descriptions are weak: "musical ensemble" (Hespèrion XXI, Il Giardino Armonico), "string quartet" (Hagen Quartett).
- English Wikipedia article: 52 of 52 persons, 32 of 33 ensembles.

## Picture

| | With P18 | No credit needed (public domain, CC0) | CC BY-SA | CC BY | Other (FAL, "Attribution") |
| --- | --- | --- | --- | --- | --- |
| Persons | 50 of 52 | 6 | 33 | 9 | 2 |
| Ensembles | 26 of 33 | 5 | 13 | 7 | 1 |

- Composers had 9 of 13 public-domain portraits. Performers are living or recent, so their pictures are recent photos with a credit duty. The credit rules of the composer research apply. FAL (Free Art Licence) is also share-alike.
- No P18: Morton Gould, Kristian Bezuidenhout, and 7 ensembles (Les Arts Florissants, Orchestre Révolutionnaire et Romantique, RIAS Kammerchor, Monteverdi Choir, Concentus Musicus Wien, Alban Berg Quartett, Chor des Bayerischen Rundfunks). P154 (logo) exists for 7 of 33 ensembles.
- Subject, read from file names only, not viewed: the Berliner Philharmoniker P18 is the Philharmonie building. LSO shows the Barbican Hall. The Academy of Ancient Music shows a portrait of J. C. Pepusch. Quatuor Ébène is a video still. Kirill Petrenko's P18 is the whole orchestra at the Brandenburg Gate. Carlos Kleiber's is a recording session.

## Request cost

The same as for composers: 1 search for each name or split part. Then one SPARQL request for the facts of 85 items, and one Commons request for the licences of 50 files.

## Risks for ADR 0017

1. The face-centred picture fails for many ensembles and some persons: a building, a hall, a group photo, or the wrong subject. Vision finds no face or many faces. The page needs a rule for no face and for many faces.
2. 88 % of performer pictures (65 of 76 files) need a credit. About must show author and licence for almost every performer.
3. ADR 0017 gives the surname rule ("matched through its works") for composers only. A one-word performer tag can match an actor. The page needs the role filter, and the listener's choice when two candidates remain.
4. The performer page needs a split of album-wide strings in the app. The split is a heuristic and fails on shared endings ("Chor und Symphonieorchester …").
5. Ensembles have no life dates. The description line needs "founded" years from P571 and P576.

## Unproven

- Sample bias: all names are famous. P434 and P18 shares for local ensembles, young soloists and early-music groups are unknown.
- Pictures not viewed. Face detection not run.
- Rejoin rule on surname lists. Role filter beyond 4 surnames.
- Auto-accept for one-word tags.

## Sources

- Wikidata API and CirrusSearch `haswbstatement` (https://www.wikidata.org/w/api.php, https://www.mediawiki.org/wiki/Help:Extension:WikibaseCirrusSearch).
- Wikidata Query Service, Commons API `extmetadata`.
- OpenSubsonic Child and Contributor responses (https://opensubsonic.netlify.app/docs/responses/child/, https://opensubsonic.netlify.app/docs/responses/contributor/).
- Navidrome v0.64.2 `resources/mappings.yaml` (link above).
- Licence duties, User-Agent and rate limits: see `../wikidata-composer-facts/README.md`.
- Live probes on 2026-11-04: `probe.py`.
