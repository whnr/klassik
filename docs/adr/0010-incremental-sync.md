# 0010. Sync at start only when the server changed

Date: 2026-10-18. Decided by code for sz-rs30.1.24; Flo asked for it on 2026-10-17.

## Context

A full sync takes 2 to 5 s (see 0002). The API cannot list the tracks that changed since a date.

## Decision

- At each sync, Klassik stores a change marker: the `lastModified` date of `getIndexes` and the `lastScan` date of `getScanStatus`.
- At start, Klassik asks for the marker. If it equals the stored one, the cached library stays. Otherwise a full sync runs.
- Pull to refresh always runs a full sync.
- If the server gives no marker, a full sync runs.

## Consequences

- A star or rating from another app does not change the marker. It shows after a pull to refresh.
- The marker is read before the pages, so a scan during a sync shows at the next start.
