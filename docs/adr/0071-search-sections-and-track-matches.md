# 0071. Search shows each kind in its own section; a track title finds its work

Date: 2026-11-21. Bead: sz-rs30.1.147.6.
Replaces the recordings under Albums of [0067](0067-search-results-and-modal-sheets.md), from Flo's decision and from the agent choice.
Replaces the track titles of albums in [0025](0025-search-field-and-filter-sheet.md).

## Context

Flo tested 0.19.0 and wrote notes on agents/claude/klassik-0.19.0-tests.md.
Search showed works under Albums, as rows of their recordings.
"Elise" gave an album and a work, both under Albums, and no row said why the album matched.
The album matched on a track title, and the WORK tag of the work did not hold "Elise".

## Decision

### Flo decided

- Typed sections: "I do not expect work under albums", and "The album section is showing stray works that appear on the album. Shall only show albums."
  Search shows Composers, Performers, Works, then Albums. Albums holds only albums.
- Works above Albums: "if I search for this, I actually expect a work in a work section above the album section".
- Favourite recordings (desk answer 7): they show only inside their work. Search has no section for recordings.
- Movements: "We have to rethink what search means for searching movements. Mostly not needed."

### Agent choices (not yet confirmed by Flo)

- A work also matches on the titles of its tracks. Such a work comes after the works that match on their own words.
- The row of a work that only a track title found shows that title as a third line, "Track: …".
- An album matches on its title and its artist, and on the titles of its tracks without a WORK tag.
  A tagged track title finds its work, not its album. The track line shows here too.

## Consequences

- "Für Elise" finds the Bagatelle in A minor under Works, with the track title that holds the nickname.
- A recording without a WORK tag is still found through its album, as ADR 0025 requires.
- The filters count the recordings of the works, people and albums that the text found (ADR 0029).
- A section that folds away on a tap is a separate feature request.
