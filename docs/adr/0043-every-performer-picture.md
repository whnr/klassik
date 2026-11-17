# 0043. A performer page shows every picture

Date: 2026-11-17. Decided by Flo in the 0.14.0 device notes. Bead: sz-rs30.1.105.80.
Replaces the picture rule of [0019](0019-performer-facts.md).

## Context

ADR 0019 shows a performer picture only when Vision finds one face. Orchestras, ensembles and quartets often have a
group or a hall as their Wikidata picture, so their pages showed no picture. Flo: "I want those pictures too! In that
case the whole picture cropped only to fill the standard viewport. Whatever it is. We show it."

## Decision

- A person page shows the Wikidata picture of a performer, as it does for a composer, whatever the picture shows.
- A picture with one face centres on that face, as [0017](0017-composer-and-performer-pages.md) says.
- A picture with no face or with several faces fills the picture frame from its centre. It does not zoom.

## Consequences

- Face detection now only sets the framing. It never hides a picture.
- Trying the next P18 picture of an item is no longer needed.
