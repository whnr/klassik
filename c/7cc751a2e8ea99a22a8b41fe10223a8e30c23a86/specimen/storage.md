# Downloads

Rules for the downloads part of `storage.html`. The cache and picture rules are in [ADR 0051](../../docs/adr/0051-pictures-and-album-art-in-local-storage.md) and [ADR 0060](../../docs/adr/0060-early-playback-and-read-ahead.md).

- A download is a recording or an album that the listener asked for. A download never covers a whole work, because a work has several recordings.
- The cache limit does not count downloads, and the cache never drops them.
- A download that fails keeps no files, because part of a recording is no use offline.
- Signing out removes the music cache and all downloads.
- Downloads sit in Application Support, outside the backup, because the server can supply them again.
- Playing offline works for tracks in the cache or the downloads. Browsing offline uses the cached library.
