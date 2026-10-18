# 0008. Downloads and the cache

Date: 2026-10-18. Decided by Flo. Beads: sz-rs30.1.9, sz-rs30.1.37.

## Context

Klassik plays each track from a file on the device (see 0005). The listener also wants to play without the server, and to keep the storage under control.

## Decision

- Two stores. The cache holds every track that played. A download is a recording or an album that the listener asked for.
- A download never covers a whole work, because a work has several recordings.
- The cache has a size limit that the listener sets. When the cache is full, it drops the tracks played longest ago.
- The limit does not count downloads. The cache never drops them.
- The Local Storage screen shows the cache size, the limit, a Clear Cache button, and the downloads with removal.
- Works, recordings and tracks show a small mark when they play without the server.
- Signing out removes the cache and all downloads.
- A download that fails keeps no files, because a part of a recording is of no use offline.

## Consequences

- Playing offline works for tracks in either store. Browsing offline uses the cached library.
- Downloads sit in Application Support, outside the backup, because the server can supply them again.
