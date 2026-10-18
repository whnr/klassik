# 0002. Sync the whole library into a local cache

Date: 2026-10-17. Decided by Flo. Beads: sz-rs30.1, sz-rs30.1.2, sz-rs30.1.24.

## Context

The work index needs every track and its classical tags. OpenSubsonic has no endpoint that returns works. Klassik must work with any OpenSubsonic server.

## Decision

- Klassik reads only OpenSubsonic standard fields.
- At each launch, Klassik shows the cached library, then fetches all tracks again. It uses `search3` with an empty query, 500 tracks a page.
- The cache is one JSON file in Application Support, keyed by server and user.
- State that Subsonic can hold stays on the server: stars, ratings, play counts. The device keeps only the filter rules and, later, the enrichment cache.

## Consequences

- A full sync of 8,961 tracks takes 2 to 5 s on music.whnr.de. Flo accepts this.
- The API has no "changed since" query for tracks. An incremental sync can only skip a sync when nothing changed (sz-rs30.1.24).
