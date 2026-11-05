# 0019. Performer facts from Wikidata

Date: 2026-11-04. Decided by Flo after research. Beads: sz-rs30.1.74.13, sz-rs30.1.74.14, sz-rs30.1.74.15.

## Context

ADR 0017 gives a performer page a picture around the face, a description and years from Wikidata. Research on 85 known performers found the right item for every name with a search filtered by `haswbstatement:P434`, and for 87 of 94 names without the filter. P434 is the MusicBrainz artist ID on the Wikidata item. Some P18 pictures show a hall, a building or a whole orchestra.

## Decision

- The performer search filters Wikidata items by P434. This does not break the rule that no view depends on MusicBrainz IDs: the app reads no ID from the tags and never calls MusicBrainz.
- When the filtered search finds nothing, the search runs again without the filter.
- When neither search finds the performer, the performer page shows the tags only, without Wikidata facts. Many lesser-known performers have no Wikidata item.
- The performer page shows a picture only when it is a portrait: one face. A picture with no face or with many faces shows no picture.

## Consequences

- The app runs face detection with Vision on the device before it shows a performer picture.
- A Wikidata item can have more than one P18 picture. Trying the next one when the first is no portrait is a later option.
- Splitting album-wide artist strings and filtering junk tags belong to outside data (sz-rs30.1.75).
