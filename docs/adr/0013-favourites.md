# 0013. Favourites and the recording order

Date: 2026-10-31. Decided by Flo. Replaces the first favourites decision. The offline rules are replaced by [0052](0052-favourites-stay-in-the-app.md).

Status: Proposed. This text removes the manual order of recordings. It becomes Accepted when Flo has reviewed it.

## Context

The listener likes composers, performers, works, recordings and albums. Navidrome stores a star on songs, albums and artists. A composer and a performer are artists. A work has no ID on the server. A star has no scale and no order. The rating field is a separate 1 to 5 number. A bookmark is one resume position per song, and other apps use it.

## Decision

- A favourite is a star. Klassik does not use ratings or bookmarks.
- A favourite composer, performer or album is a star on its artist or album. A favourite work is stored on the device.
- A favourite recording is a star on all its tracks. A work can have several favourite recordings.
- A work lists its recordings in this order: favourites, newest first; then recordings with a favourite performer; then recordings from a favourite album; then the rest, newest first. A row that rises because of a performer or an album shows why.
- The reference recording is the first recording in that list. It plays when the listener plays or queues the work without a recording.
- An album favourite does not star its tracks.
- The server is right. At launch and on return to the foreground, `getStarred2` reads all stars. A recording that loses its star elsewhere loses its place among the favourites.
- A change made offline shows at once and waits in a queue. The queue goes to the server in order when it is reachable. Technical details show the changes that wait.
- A listening note sits on one recording: a movement and a time, with an optional end. It is text only and stays on the device.

## Consequences

- Other apps see and change the stars. They do not see favourite works, or listening notes.
- An export of listener data must read the server and the device.
- A work without favourites plays the newest recording, not the oldest.
- Setting a favourite recording no longer removes the star from other recordings of the work.
