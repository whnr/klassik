# 0008. Offline storage

Date: 2026-10-18. Flo decided downloads and the cache; bead sz-rs30.1.9 and sz-rs30.1.37.

## Context

A listener plays classical music on a train, without a server. Tracks are large. The device has limited space. Flo wants to choose what stays and what the app may remove.

## Decision

- Downloads exist only for a recording or an album. A work has no download.
- A download keeps the original file in Application Support/downloads. The backup excludes it.
- Every played track goes into a separate cache.
- The listener sets a maximum cache size. The default is 2 GB.
- When the cache grows past the maximum, it removes the least recently played tracks first.
- Downloads do not count toward the maximum. The cache never removes a download.
- A track that is both cached and downloaded lives once, as a download.
- The Local Storage screen shows the cache with Clear Cache, and the list of downloads.
- Sign-out clears the cache and removes all downloads.

## Consequences

- The system may empty the caches folder, so only a download is a promise.
- A downloaded recording plays without the server. A cached track may play without it.
- A new sign-in must download recordings again.
