# 0004. How tracks group into works and recordings

Date: 2026-10-17. Decided by Flo for TB2. Beads: sz-rs30.1.3, sz-rs30.1.8.

## Context

Few tracks carry work tags. On music.whnr.de, 9% of classical tracks have a WORK tag and none have MOVEMENT tags. A WORK tag can be as short as "Op. 67".

## Decision

- Work key, in this order: the MusicBrainz work ID; else composer plus WORK tag; else composer plus album.
- A track without a WORK tag makes its album one work, listed under "Albums Without Work Tags".
- A recording is the tracks of one work on one album, in disc and track order.
- A track that the server holds twice (same disc, track and title) plays once.
- The work shows context from the track titles and album names, because the WORK tag alone can be unclear.

## Consequences

- The same work in two languages gives two works until TB6 (sz-rs30.1.8) adds catalogue numbers.
- The data was measured on the old library only. Measure again after the Presto downloads (sz-rs30.1.29).
