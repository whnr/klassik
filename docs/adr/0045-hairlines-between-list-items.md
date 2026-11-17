# 0045. Hairlines separate list items only

Flo decided this in the 0.14.1 test notes. Bead: sz-3hcq.4.
This refines the list rules of [0030](0030-type-and-spacing.md).

## Context

Headings and performer subtitles drew hairlines. Flo wants hairlines only between list items.

## Decision

- Draw a hairline before each list item except the first.
- Draw no hairline around headings, subtitles, covers, playback capsules, or section boundaries.
- Keep the system list components and their row actions.

## Consequences

Content pages identify consecutive list items explicitly. The specimen already separates adjacent rows only.
