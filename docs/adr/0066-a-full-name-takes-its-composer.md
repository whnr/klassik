# 0066. A full-name tag takes its composer

Date: 2026-11-20. Decided by Flo in the 0.16.0 device notes. Bead: sz-rs30.1.131.2.
Adds to the name match of [0017](0017-composer-and-performer-pages.md). The surname rule of 0017 stays.

## Context

Wikidata gives the occupation composer to many relatives and friends of a composer. The name search for
"Ludwig van Beethoven" finds seven items. All of them carry that occupation. His grandfather has the same full
name. Klassik showed the pick list "Which composer is this?" for Beethoven.

Flo's decision: "Expected: the only composer match by name shall match!"

## Decision

- The works decide first, as 0017 says: when the MusicBrainz composers of the works lead to one Wikidata person,
  the tag takes that person.
- Else a tag of two or more words takes the one search hit whose name is the tag. Hits with another name never
  count, so relatives and friends with the same family name drop out.
- A namesake whose description names the tag loses, such as "grandfather of composer Ludwig van Beethoven". The
  description tells that the item is a person around the composer.
- Two or more namesakes that remain go to the pick list, without the hits that have another name.
- Each row of the pick list is a tap target for its whole width, title included.
- A pick list saved before this rule is settled again on the device when the rule settles it. The listener's
  choice and "Choose Composer Again" stay.

## Consequences

- A full-name tag without MusicBrainz IDs gets its composer from the first lookup. No pick list waits for the
  MusicBrainz pass.
- The occupation filter of the search stays. It keeps people who never composed out of the hits.
- "Choose Composer Again" still lists every hit of the search.
