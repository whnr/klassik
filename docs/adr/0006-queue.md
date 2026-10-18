# 0006. The queue holds recordings

Date: 2026-10-18. Proposed by code for TB3; Flo tests it in 0.6.1. Beads: sz-rs30.1.5, sz-rs30.1.26.

## Context

A listener plays several works in a row. Shuffle must not mix movements of different works.

## Decision

- A queue item is one recording of one work. A whole album is one item too.
- Play replaces the queue. Play Next and Add to Queue add to it, as in Apple Music.
- A work without a chosen recording queues its oldest recording until TB4 (sz-rs30.1.6) adds the reference recording.
- Shuffle puts works in random order. The movements of each work stay in order.
- After the last movement, the next item starts. Klassik does not join two items without a gap.

## Consequences

- The queue lives on the device. The Subsonic play queue on the server is not used yet.
