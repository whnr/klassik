# 0067. People lead Search; sheets block the page

Date: 2026-11-21. Beads: sz-rs30.1.135.1, sz-rs30.1.135.3, sz-rs30.1.135.5, sz-rs30.1.135.6, sz-rs30.1.135.7.
Replaces the result order of [0025](0025-search-field-and-filter-sheet.md) and the taps on the results above its sheet.
The recordings under Albums are replaced by [0071](0071-search-sections-and-track-matches.md).

## Context

Flo tested 0.18.0 and wrote notes on agents/claude/klassik-0.18.0-tests.md.
He could not distinguish Filters from the page behind it.
Back did not close Filters, and he could not find a recording in Search.

## Decision

### Flo decided

- Dimmed modal sheets: "Do what good accessibility tells us to do and make it the same for all sheets that overlay other content.
  It's ok to not be able to interact with the rest of that aligned with good UX".
  Every sheet over content uses native modal dimming and blocks interaction with the page behind it.
- Back with Filters open: "the search sheet overlay stays when going back in pages.
  You can swipe back but you can[not] use the back button".
  Leaving Search closes Filters. Returning never restores an open sheet.
- Result order: "people sort above works. First composers then performers the[n] works then albums".
  Search shows Composers, Performers, Works, then Albums.
- Hidden works: "remove the hidden work count. Not needed in a search". Search shows no hidden-work count.
- Recordings: "I looked for a recording and could not find the fermata [because] there are none.
  They can go under albums for now". Matching recordings appear under Albums.

### Agent choices (not yet confirmed by Flo)

- Filters has a Back button inside the sheet, as the word "Back" before its title.
  Back closes Filters, then returns to the page before Search.
  The modal sheet blocks the back arrow of the page, so the sheet needs its own way back.
- A person who composes appears only under Composers, also when they perform. One person gets one row.
- Search lists every recording that matches the search under Albums, not only favourites.
  This follows Flo's note. Each favourite recording shows its fermata, and each row opens its recording page.

## Consequences

The system controls dimming and accessibility focus, including Increase Contrast.
Results still update behind Filters. The listener closes Filters to use them.
The term lists still use the text and the other conditions, as ADR 0029 requires.
