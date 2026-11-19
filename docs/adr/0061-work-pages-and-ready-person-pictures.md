# 0061. Work pages and ready person pictures

Flo decided these rules in the 0.14.5 test notes. Beads: sz-rs30.1.129.1, .3, .4 and .5.
Replaces the person-picture Low Data Mode rules of [0059](0059-covers-and-pictures-before-pages.md).
Refines the title spacing of [0030](0030-type-and-spacing.md).

## Context

Flo rejected album art and Play Album on work pages.
Large person pictures appeared after the page started sliding in.
The top blur touched titles on pages without pictures.

## Decision

- A work page has no album art and no Play Album button. Play uses its reference recording.
- Each recording row keeps its own album art. Recording and album pages keep their covers and playback controls.
- Prepare person pictures before page visits. Decode them at the display size and keep their face framing ready.
- Low Data Mode permits person pictures. It restricts album art under the existing cover policy.
- Keep the system top blur. Move titles without pictures below it with the specimen's large top gap.

## Consequences

Person pages can draw prepared pictures in their first frame.
Picture preparation resumes after pull to refresh. Failed requests preserve valid stored pictures.
The work specimen and app share the reduced header and title spacing.
