# 0011. Composition dates from MusicBrainz and Wikidata

Date: 2026-10-19. Scope by Flo (bead sz-rs30.1.7); the rules below by code. Bead: sz-rs30.1.7.

## Context

Tags carry no composition date. A timeline needs one for each work. Klassik keeps no catalogue of its own: outside data only fills gaps, and missing data gets fixed upstream.

## Decision

- A work with a MusicBrainz work ID in its WORK tag is looked up by that ID.
- A movement ID walks up to its work, through a `parts` relation with the `movement` attribute only. A plain part, such as one étude of an opus set, stays a work of its own.
- The composition date is the date of the composer relation. Without it, Klassik takes the earliest Wikidata publication date (P577) of the item with that MusicBrainz ID (P435).
- A work without an ID is searched by the composer's surname and the catalogue number in its title. Thematic catalogues (BWV, RV, K., D., Hob., KK and others) come before the opus number.
- In search results, a colon in a title marks a movement. If any result is a whole work, the movements drop. A best match of score 75 or more links at once if no other match of 75 or more has another title: MusicBrainz holds some works twice, and scores an exact title low when it spells hyphens differently. Other matches wait for the listener to confirm once. The listener can turn down a match.
- A composer's dates come from the composer relation of their works, else from a search by full name or alias with a single exact match.
- Facts are cached on the device by MusicBrainz ID and fetched once. "Look Up Again" fetches one work again after a fix in MusicBrainz.
- Requests to each service wait for each other, one every 1.1 seconds, with a User-Agent that names Klassik.
- A year that the listener types stays on the device and wins over both sources.
- The timeline shows tagged works only. A composer belongs to the period of the year they turned 35, or of their death if it came first. The periods start in 1600, 1750, 1820, 1910 and 1975. A work without a date sits inside its composer's lifetime and is marked approximate.

## Consequences

- The first lookup of a large library takes minutes: about one request per work, plus one per composer.
- Wikidata P577 is a publication date. It can be years after the composition.
- A work without a catalogue number in its title and without an ID is not searched. It shows on the timeline only inside its composer's lifetime.
- Albums without WORK tags are not on the timeline.
