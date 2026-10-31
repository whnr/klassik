# Listener data in Navidrome through OpenSubsonic

Bead: sz-rs30.1.74.3. Checked 2026-10-31 on Navidrome 0.64.2 (linux amd64, started with `scripts/fixture-server.sh`). Probe: `probe.py` in this folder. It needs a fresh server and uses the fixture admin user from that script. A second user, `other`, comes from Navidrome's admin API. That is test setup only.

## Answer

Every kind of listener data is stored per user. No other user sees it, except a public playlist and the now-playing list.

| Data | Attaches to | Other users see it | Limits |
| --- | --- | --- | --- |
| Star | Song, album, artist. A composer is an artist, so it can be starred. | No | A second star replaces the timestamp. An unknown ID is accepted and ignored. |
| Rating | Song, album, artist (composer too) | No. Only `averageRating` on songs mixes all users. | Spec: 1 to 5, 0 removes. Navidrome stores any integer (6, 100, -1). It rejects a decimal. |
| Playlist | Own list of songs | Only if public. Read-only for them. | No limit seen up to 3000 songs. Duplicates allowed. |
| Bookmark | One song. One per user and song. | No | A new one replaces the old one. No count limit seen. |
| Play queue | One per user, not per client | No | No limit seen up to 3000 songs. Records the last client name. |
| Play count | Song, album. Not artist or composer. | No | Counts only `submission=true`. |
| Last played | Song, album | No | A later play sets it. An older `time` does not move it back. |
| Now playing | One song per call | Yes, `getNowPlaying` lists every user | Not a count. Does not change the play count. |

What this means for marks and notes:

- A composer can be starred and rated through `artistId`. `getStarred2` returns it as an `artist` with `roles: ["composer"]`.
- A work cannot be starred, rated or bookmarked. The server has no work entity with an ID. A client must store a work mark itself, or mark a song.
- A listening note with free text fits the bookmark `comment` only once per song. There is no position list per song. A second bookmark replaces the first.
- Rating is not a safe field for a custom range. The server accepts values outside 1 to 5. A client must clamp.

## Star

Spec: `star` (id, albumId, artistId; "Attaches a star to a song, album or artist").

- Proven: `star` with a song ID, album ID, performer artist ID and composer artist ID all return ok. `id` and `albumId`/`artistId` reach the same lookup (source: `media_annotation.go`, `setStar` switch on artist, album, playlist, else song).
- The composer is an `ArtistID3` with `roles: ["composer"]`, `albumCount: 0`. `getStarred2` returned it under `artist` with `starred` set. `getArtist` shows the same `starred`.
- `getStarred2` returned `{artist: 2, album: 2, song: 1}` for the stars set. After `unstar` of the song and the composer, `{artist: 1, album: 2}` stayed.
- `getAlbumList2 type=starred` works. `search3` shows `starred` on songs.
- `star` of an unknown ID returns ok. Nothing is stored.
- A second `star` on a starred song changed the timestamp (proven: `False`).
- A second user saw empty `getStarred2` and no `starred` on the song. Stars are per user.

## Rating

Spec: `setRating`. "The rating between 1 and 5 (inclusive), or 0 to remove the rating." The ID may be a file or a folder (album or artist).

- Proven: ratings on a song, an album, a performer and a composer all return ok and come back as `userRating` in `getSong`, `getAlbum`, `getArtist`.
- Values 6, 100 and -1 return ok and come back unchanged. Source: `SetRating` reads `p.Int("rating")` and passes it on. `media_annotation.go` has no range check.
- `2.5` fails with error 0. `0` removes `userRating` from the reply. An unknown ID gives error 70.
- Per user: the second user saw no `userRating`. `getAlbumList2 type=highest` listed the album for me and was empty for the other user.
- `averageRating` appears on songs. With my 4 and the other user's 2 it was 3. A rater can see the mean of all users, not who rated.

## Playlists

Spec: `createPlaylist`, `updatePlaylist`, `getPlaylist(s)`.

- Fields kept: `name`, `comment`, `public`, `owner`, ordered `entry` list, `songCount`, `duration`, `created`, `changed`, `readonly`. `public` is absent when false.
- Order is the list order. Duplicates stay (index sequence `[0,1,2,0,0]`). `songIndexToRemove` removes by position. There is no move call. `createPlaylist` with `playlistId` and a new `songId` list replaces the order and keeps name and public flag (proven: `[5,4,3]`).
- A private playlist is invisible to another user: `getPlaylists` empty, `getPlaylist` error 70. A public one is readable (`readonly: true`). Their `updatePlaylist` fails with error 50.
- Name is required (an empty request gives error 0). Unicode works.
- Size: 3000 songs created and returned in full. A 5000-character comment was stored. I did not find a limit. I tested no larger value. Large lists need POST; the probe used it.
- A playlist keeps only songs. An unknown ID is dropped silently. An album ID adds nothing.

## Bookmarks

Spec: `createBookmark`. "If a bookmark already exists for this file it will be overwritten." "Bookmarks are personal and not visible to other users."

- Proven: two bookmarks on one song left one, with the second position and comment. Different songs each keep one. 25 bookmarks coexisted.
- Fields: `entry` (the full song), `position` (ms), `comment`, `username`, `created`, `changed`.
- Only a song ID works. An album ID or unknown ID gives error 70.
- Accepted without complaint: position -5 and a position beyond the song length. A 3000-character comment was stored.
- The other user saw an empty `getBookmarks`.
- `Child.bookmarkPosition` appears on the song. The spec says "in seconds". Navidrome returned 5000 for a bookmark set at 5000 ms. So it returns milliseconds. A client must not trust the unit and should read `getBookmarks` instead.

## Play queue

Spec: `savePlayQueue`: ids, `current`, `position` in ms. "Saves the state of the play queue for this user." Source: `bookmarks.go`.

- One queue per user. Proven: a save from client "Klassik-B" replaced a queue from "Klassik-A". `changedBy` named the last client (the `c` parameter).
- `getPlayQueue` returns `current` (song ID), `position`, `username`, `changed`, `changedBy` and full `entry` songs.
- If `current` is not in the ID list, Navidrome uses the first song (`currentIndex := 0`). Proven. If `current` is missing it does the same. `position` defaults to 0 and is then absent.
- `getPlayQueueByIndex` works. It returned `currentIndex: 2`, `position: 77`.
- A call with no IDs clears the queue. `getPlayQueue` then returned an empty queue with `changed` 0001-01-01.
- Another user has their own, empty queue.
- 3000 songs saved and returned. No limit seen.

## Play counts and scrobbles

Spec: `scrobble`: `id`, `time` (ms), `submission` (default true).

- `submission=false` is a now-playing notice. It changed no count and no `played`. It showed in `getNowPlaying` for the other user with `username`, `minutesAgo` and `playerName`. Only the first ID counts (source log message).
- `submission=true` added 1 to `playCount` and set `played` to the given `time` (proven: 2023-11-14 stored). Without `time` the server clock is used.
- A play with an older `time` raised `playCount` but left `played` at the newer value.
- Several IDs with several `time` values work. A different number of times and IDs is an error in the source.
- Plays count on songs and on the album (the album count is the sum for its songs: 3 after 3 plays). `getAlbumList2` types `frequent` and `recent` use them.
- Artists and composers show no `playCount` and no `played`, and no `starred` until starred. The spec lists no `playCount` for `ArtistID3`.
- A second user saw no `playCount` and empty `frequent`. Counts are per user.
- An unknown ID returns ok.
- The server applies no minimum play time. The client decides when a play counts.

## Unproven

- Larger limits than 3000 for playlists and queue. Navidrome config may set limits on a real server.
- Navidrome playlist and scrobbler behaviour with external scrobblers (Last.fm, ListenBrainz).
- Other servers than Navidrome 0.64.2.
- `time` in the future, and playlists as a star or rating target (source accepts a playlist ID).
- Whether `getNowPlaying` entries expire. The probe saw one entry after a later submission.
- The spec pages were read through a summarising fetch, not the raw OpenAPI file. The Navidrome source quotes also came through a summarising fetch.

## Sources

- OpenSubsonic endpoints `star`, `setRating`, `scrobble`, `savePlayQueue`, `createBookmark`; responses `Child`, `ArtistID3` (https://opensubsonic.netlify.app/docs/).
- Navidrome v0.64.2 `server/subsonic/media_annotation.go` and `server/subsonic/bookmarks.go` (github.com/navidrome/navidrome).
- Probe on Navidrome 0.64.2: `star`, `unstar`, `getStarred2`, `setRating`, playlist calls, bookmark calls, play queue calls, `scrobble`, `getNowPlaying`, `getAlbumList2`, `getSong`, `getArtist`.
