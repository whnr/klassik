# 0069. No Shuffle and no performer list before 1.0

Date: 2026-11-21. Decided by Flo in his specimen answers. Beads: sz-rs30.1.105.33.6, sz-rs30.1.105.33.8.
Replaces the Shuffle rule of [0006](0006-queue.md).
Replaces the Performers page of [0057](0057-search-apart-from-place-tabs.md).

## Context

The specimen draws no Shuffle button, but the app showed one on Library and on the composer page.
The empty Search page linked to a list of all performers. That list came before Search found people.
Search now finds every composer and performer by name ([0067](0067-search-results-and-modal-sheets.md)).

## Decision

- No Shuffle. Flo: "Remove for now." After 1.0 it comes back as discover, not as shuffle.
- No performer list. Flo: "now that we have a full search, we don't need the performers list anymore on the search
  page; it was a weird stopgap."
- Search results and the pages that name a performer are the ways to a performer page.

## Consequences

- Library and the composer page have no Shuffle button in the bar.
- The empty Search page shows the hint or the recent searches only.
- The Library page design decides how a listener discovers performers.
- The rows of the performer list leave the pages of [0046](0046-composers-first-and-shown-performers.md).
