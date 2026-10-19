# 0012. Look up works composer by composer

Date: 2026-10-19. Decided by Flo ("batch lookup now"). Bead: sz-rs30.1.64. Changes the lookup order of [0011](0011-enrichment.md); its matching rules stay.

## Context

A search for each work costs one request a second. A live run on Flo's library took 14 minutes for 242 works. Thousands of works would take hours.

## Decision

- Klassik looks up the library composer by composer.
- A composer with two or more open works gets a list of all their works from MusicBrainz, 100 works per request, with dates and relations. Klassik matches on the device.
- Klassik lists a composer only if the list costs fewer requests than a search for each open work. Else, and when the list fails, each work is searched as in 0011.
- With a complete list, a work whose catalogue number no listed title carries matches by the words of its title, without the catalogue number. Such a match links only if it is the only one.
- Wikidata gets one query for up to 50 undated works.
- Home > MusicBrainz shows the progress, the counts, and the works to confirm or without a match. "Look Up Missing Again" asks again for all works without a match. Matches the listener turned down stay turned down.

## Consequences

- Most works cost no request of their own. A composer with 725 works, such as Chopin, costs 8 requests.
- A composer with many works and few open ones is still searched work by work.
