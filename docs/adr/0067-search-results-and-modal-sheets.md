# 0067. People lead Search; sheets block the page

Decided by Flo, 2026-11-21. Beads: sz-rs30.1.135.1, sz-rs30.1.135.3, sz-rs30.1.135.5, sz-rs30.1.135.6, sz-rs30.1.135.7.
Replaces the result order and live-background interaction rules of [0025](0025-search-field-and-filter-sheet.md).
Refines the recording results of [0029](0029-search-at-the-top.md).

## Context

Flo tested 0.18.0 and could not distinguish Filters from the page behind it.
He could not find favourite recordings in Search.

## Decision

- Every sheet over content uses native modal dimming and blocks interaction with the page behind it.
- Filters provides Back inside the sheet. Back closes Filters, then returns to the page before Search.
- Leaving Search closes Filters. Returning never restores an open sheet.
- Search shows Composers, Performers, Works, then Albums. A person who composes appears only under Composers.
- Matching favourite recordings appear under Albums with their fermata and open their recording page.
- Other recordings get no row. They open through their works and albums, and a row for each would bury the albums.
- Search shows no hidden-work count.

## Consequences

The system controls dimming and accessibility focus, including Increase Contrast.
Results still update behind Filters. The listener closes Filters to use them.
The term lists still use the text and the other conditions, as ADR 0029 requires.
