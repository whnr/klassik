# 0053. Fetch covers before pages need them

Date: 2026-11-18. Flo's cover rule, recorded for sz-rs30.1.117.7. Implementation belongs to 0.15, after 0.14.3.
Replaces the album art fetch, key and eviction rules of [0051](0051-pictures-and-album-art-in-local-storage.md).
The open questions below need Flo's answers before implementation.

## Context

Flo requires every album cover ahead of use, indexed by album and disc, with shared files for identical covers.
He also requires persistent track links for embedded covers discovered when tracks load.
Flo: "We don't want to ever have to load covers late. This app is for beauty."

[PR 84](https://github.com/whnr/klassik/pull/84) introduced ImageStore and separate Local Storage limits.
[PR 86](https://github.com/whnr/klassik/pull/86) stops fetching when remaining space falls below the mean stored file size.
Both rules can leave albums without covers until a page requests them.
That conflicts with Flo's requirement.
[0017](0017-composer-and-performer-pages.md) uses covers in album lists.
[0014](0014-player.md) and [0028](0028-mini-player-pill.md) require stable player cover positions.

## Decision

### Fetch during library sync

- Library sync schedules every album cover, including albums outside the classical filter, before any page needs it.
- Resolve album and disc sources from OpenSubsonic standard metadata. Fetch their covers through standard cover requests.
- Fetch each distinct source once per sync pass. Reuse unchanged stored covers and resume missing work after interruptions.
- A disc uses its own cover when metadata supplies one. Otherwise it links to the album cover.
- Never fetch whole audio files merely to discover embedded art during library sync.
- Keep one page-sized stored representation, as in 0051. Decode smaller sizes locally for rows and the pill.
- A page reads the local store only. Opening a page never starts a cover request.

### Logical keys and shared files

- Scope every logical key to the server and account. Passwords and signed URLs never form persistent identities.
- The cover lookup key is album identity plus disc number, within that account.
- Use the server album ID when available. Otherwise persist the library's album identity; do not key by title alone.
- Keep a separate unknown-disc key when metadata lacks a disc number. Do not assume it means disc one.
- Each album-disc database entry links to a content hash. Each track entry can hold its own cover hash.
- ImageStore stores one file per SHA-256 hash of the stored image bytes, independent of logical keys.
- All discs with identical stored bytes link to that file. Twenty discs sharing one cover consume one file.
- Reuse the same stored representation for a shared source. Visually similar images with different bytes need not share files.
- Commit database links only after the file write succeeds. Remove files only when no album, disc or track references them.

### Embedded track covers

- When a track file loads for playback or download, inspect its embedded art before presenting the loaded track's cover.
- Validate and store embedded art through the same content-hash store. Persist its hash on the track's database entry.
- For that track, the embedded cover replaces the album-disc cover in the same visible slot when it becomes available.
- Keep the slot's size and position. Show the existing cover until the replacement is ready; never flash a placeholder.
- This replacement is an explicit refinement of an existing cover, not a late fetch of its missing album cover.
- Do not overwrite the shared album-disc link or other tracks' links. A shared file must remain immutable.
- On later loads, resolve the track hash first, then the album-disc hash. Keep the extracted cover after audio eviction.
- Missing or invalid embedded art leaves the existing cover unchanged.

### Local Storage and limits

- Count unique stored cover files once in Album Art, including extracted track covers. Keep the separate Pictures store unchanged.
- Album Art keeps No Limit as its default. A finite limit cannot evict covers referenced by the current library.
- At the limit, keep every referenced album, disc and track cover, including covers that have never appeared on screen.
- Remove unreferenced files first. Continue fetching missing library covers even when referenced art exceeds the selected limit.
- Flo's complete-cover rule wins over the limit. The finite Album Art limit becomes a target, not a hard cap.
- Local Storage must show actual usage and explain excess usage. Never silently claim that the target bounds storage.
- This replaces 0051's oldest-used eviction and stop-at-limit rules for Album Art, including PR 86's mean-file guard.
- Music and Pictures retain their limits. Low Data Mode still defers cover requests, as 0051 requires.
- Physical storage failures stop writes. Keep valid files and links, record incomplete sync work, and retry when storage permits.
- Signing out removes account cover links and files. Explicit Album Art Clear removes its files and invalidates their links.

### First presentation and placeholders

- Resolve and decode local covers before presenting a page's cover slots. Pages never show placeholders awaiting network requests.
- During initial sync, interrupted sync, Low Data Mode or storage failure, use a fixed placeholder for unavailable covers.
- Use that placeholder also when the server supplies no valid cover. Keep the cover slot's dimensions unchanged.
- Freeze each shown slot's cover choice for that presentation. Background sync never replaces its placeholder while it remains visible.
- A later page presentation can use newly stored art. Preserve existing covers during sync and refresh.
- The embedded replacement above is the sole cover refinement during a presentation.

## Consequences

- Normal browsing shows local covers from the first frame, including offline. It causes no cover network traffic.
- Initial sync needs more time and data. Limited connectivity and storage can prevent complete covers; stable placeholders expose that constraint.
- Referenced covers can exceed the selected target. Complete artwork takes priority over a strict Album Art storage bound.
- ImageStore needs immutable shared files and persistent database references. Its current logical-key filenames cannot provide content deduplication.
- This record changes no app code, app version, layout or colour rule.

## Open questions for Flo

1. May referenced Album Art exceed a finite limit? Recommended: yes; show the excess and explain the target in Local Storage.
2. Should browsing remain available before initial cover sync finishes? Recommended: yes, with fixed placeholders until the next page presentation.
3. Should Low Data Mode still defer missing covers? Recommended: yes; preserve stored covers and show fixed placeholders for missing ones.
4. After Album Art Clear, when should covers return? Recommended: at the next explicit library sync, never from opening a page.
5. Should sync refresh unchanged cover IDs? Recommended: on explicit full refresh; ordinary sync reuses them to avoid repeated downloads.
