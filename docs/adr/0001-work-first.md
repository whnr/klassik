# 0001. The work is the primary object

Date: 2026-10-17. Decided by Flo. Bead: sz-rs30.1.

## Context

Music apps show albums. A classical listener looks for a work, then picks a performance. One album can hold several works, and one work can be on several albums.

## Decision

- The app browses Composer > Work > Recordings > Movements. Albums only show where a recording comes from.
- The playback unit is the work. Play queues all movements of one recording, without gaps.
- The recordings of a work sort by recording date. Performers come first; album art is secondary.
- Klassik is for classical music only. Other music stays in other apps.

## Consequences

- The app builds the work index on the device from tags (see 0002 and 0004).
- Shuffle orders works, never movements (see 0006).
