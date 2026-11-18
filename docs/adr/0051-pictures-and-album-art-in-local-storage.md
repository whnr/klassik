# 0051. Pictures and album art in Local Storage

Date: 2026-11-17. Decided by Flo in the 0.14.0 device notes. Bead: sz-rs30.1.105.79.
Replaces the cache and screen rules of [0008](0008-offline-storage.md).
The album art fetch, key and eviction rules are replaced by [0053](0053-covers-before-pages.md).

## Context

ADR 0008 counts only played tracks as the cache. Composer and performer pictures sat in a hidden URL cache of 200
MB, and the album art came from the server each time. Flo: "pictures and date [data] count towards cache size. The
cache size is shown per type. Like iOS storage. You can set a limit for music and pictures separately." And: "cache
all album art (and add it to the cache bar) with a limit that's unlimited by default as well." Also: "I want all the
data on my phone. [...] But well respect low data mode."

## Decision

- The device keeps three caches: music (the played tracks), pictures and album art. Downloads stay apart, as in
  0008.
- Local Storage shows one bar like the iPhone storage page. Each store has a colour and a share of the bar: Music,
  Downloads, Pictures and Album Art. A list under the bar gives the size of each store. The footnote gives the
  total and the free space of the device.
- Each cache has its own limit and its own Clear button. The music limit keeps its default of 2 GB. Pictures and
  album art have no limit by default. One step past 50 GB is No Limit.
- When a cache is over its limit, the files used longest ago go first.
- Klassik keeps one copy of the art of each album, at the size of the page cover. Every view scales it down.
- After a sync, a pass keeps the art of every album of the library, classical albums first. It stops when the
  album art cache is full. It does not use a Low Data Mode connection.
- Signing out removes the album art with the music cache and the downloads. The pictures belong to no account and
  stay.

## Consequences

- Album art shows without the server once the pass has run.
- A large library can keep some hundred MB of album art. The listener sees it in the bar and can set a limit.
