# 0024. Work headings on an album page only for whole works

Date: 2026-11-07. Decided by Flo after the second specimen round. Beads: sz-rs30.1.91, sz-rs30.1.83.12.

## Context

ADR 0015 and CONTEXT.md say that an album page shows its works and their tracks in disc order. The specimen put a heading above every work. On an album of single pieces, such as a Chopin album, each heading stood above one track, and the list became twice as long with nothing gained.

## Decision

- An album page heads its tracks by work only when the album holds at least one work with two movements on consecutive tracks.
- Otherwise the album page is a plain list of its tracks in disc order, with each title as tagged.

## Consequences

- The rule reads the work tag of each track and the track order. It needs no movement count.
- A recital disc with one sonata among single pieces gets headings for every work. The tracer checks how that reads.
