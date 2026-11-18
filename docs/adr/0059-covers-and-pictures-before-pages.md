# 0059. Fetch covers and pictures before pages need them

Date: 2026-11-18. Decided by Flo for sz-rs30.1.117.7, sz-rs30.1.118 and sz-rs30.1.120. Implementation belongs to 0.15.
Replaces the image fetch, cover key and refresh rules of [0051](0051-pictures-and-album-art-in-local-storage.md).
Refines [0010](0010-incremental-sync.md) for image refreshes.

## Context

Flo requires stored album covers before use, indexed by album and disc, with shared files for identical covers.
He also requires persistent track links for embedded covers discovered when tracks load.
Pictures must load during people lookup, before the first page visit.
The goal is instant pages with local images. Missing images must never change the layout when they arrive.

## Decision

### Filter first, then fetch ahead

- Initial sign-in syncs library metadata first. Image fetching starts only after the listener first sets the classical filter.
- Schedule covers only for albums that pass that filter, as defined in [0003](0003-classical-filter.md).
- Apply that scope to background work, page requests and playback requests. Do not fetch covers for excluded albums.
- Fetch rich data and person pictures only for the library that passes the filter.
- Resolve album and disc sources from OpenSubsonic standard metadata. Fetch their covers through standard cover requests.
- Fetch each distinct source once per pass. Resume missing work after interruptions.
- A disc uses its own cover when metadata supplies one. Otherwise it links to the album cover.
- Never fetch whole audio files merely to discover embedded art during library sync.
- Keep one page-sized stored representation, as in 0051. Decode smaller sizes locally for rows and the pill.

### Sync and refresh

- Ordinary sync checks the server change marker, as in 0010. When it changes, sync metadata and fetch new covers.
- Reuse stored covers with unchanged source identities during ordinary sync. Resume missing covers without downloading stored covers again.
- A full sync explicitly rereads all library metadata and refreshes every eligible cover, even when source identities remain unchanged.
- Pull to refresh requests this full sync. A server change alone does not require refreshing unchanged covers.
- Keep each stored image visible until its replacement is valid and stored. Never clear all images before a full sync.
- Replace files and database links safely. A failed refresh keeps the valid image and leaves the refresh pending.
- Opening a page immediately requests its missing covers. A person page moves all its covers to the queue's front.
- After Album Art Clear, the next library sync schedules missing covers. Opening a page also fetches them.

### Logical keys and shared files

- Scope cover keys to the server and account. Passwords and signed URLs never form persistent identities.
- The cover lookup key is album identity plus disc number, within that account.
- Use the server album ID when available. Otherwise persist the library's album identity; do not key by title alone.
- Keep a separate unknown-disc key when metadata lacks a disc number. Do not assume it means disc one.
- Each album-disc database entry links to a content hash. Each track entry can hold its own cover hash.
- ImageStore stores one file per SHA-256 hash of the stored image bytes, independent of logical keys.
- Twenty discs sharing identical stored bytes consume one file. Visually similar images with different bytes need not share files.
- Commit database links only after the file write succeeds. Eviction and Clear invalidate affected links.
- Replacing one link must preserve files that other links still need.

### Embedded track covers

- When a track file loads for playback or download, inspect its embedded art.
- Validate and store embedded art through the same content-hash store. Persist its hash on the track's database entry.
- For that track, the embedded cover replaces the album-disc cover in the same visible slot when ready.
- Keep the slot's size and position. Show the existing cover until the replacement is ready; never flash a placeholder.
- Do not overwrite shared album-disc links or other tracks' links. Shared files remain immutable.
- On later loads, resolve the track hash first, then the album-disc hash. Keep extracted covers after audio eviction.
- Missing or invalid embedded art leaves the existing cover unchanged.

### Local Storage and Low Data Mode

- Count unique cover files once in Album Art, including extracted track covers. Count person pictures separately in Pictures.
- Keep both existing limits, with No Limit as their default. Do not convert finite limits into advisory targets.
- Keep 0051's eviction rules and the existing stop-at-limit guard. This decision does not authorize storage above a selected limit.
- Covers are small; Flo leaves removal of the limit to a later decision.
- Low Data Mode preserves stored images and defers missing covers and pictures. Show fixed placeholders for missing images.
- When playback starts and streams, always fetch its cover, even in Low Data Mode.
- Physical storage failures stop writes. Keep valid files and links, and retry pending work when storage permits.
- Album Art Clear removes its files and invalidates links. Pictures Clear does the same for Pictures.
- Signing out removes account cover links and files. Person pictures remain account-independent, as in 0051.

### First presentation and placeholders

- Browsing remains available before the first image pass finishes. Read stored images immediately and request missing images as above.
- Every image slot has defined dimensions before and after loading. Missing or invalid images use a fixed placeholder.
- Replace a visible placeholder immediately when its image loads. Do not wait for another page presentation.
- Crop non-square covers and scale smaller covers to fit the defined slot. Image arrival never changes the layout.
- A designed placeholder belongs to 1.0. No final placeholder design is required for 0.15.
- Preserve existing images during sync and refresh. Offline pages show stored images or the same fixed placeholders.

### Person pictures

- Each people lookup downloads every found picture into ImageStore immediately, before any page visit.
- Each later lookup refreshes that person's pictures. Replace stored pictures when they change; keep valid pictures during refresh.
- A person page requests missing pictures immediately, subject to Low Data Mode and the Pictures limit.
- The same fixed-slot and immediate-replacement rules apply to pictures. Playback's Low Data Mode exception applies to covers only.
- Pictures Clear permits refilling during the next people lookup or page visit, under the same limits.
- Keep [0043](0043-every-performer-picture.md)'s rule to show every picture. This record governs fetching and storage.

## Consequences

- Complete image passes let pages show images immediately, including offline. Incomplete passes permit immediate requests without layout shifts.
- Filter-first fetching avoids work for excluded albums and people.
- Finite limits, Low Data Mode and storage failures can leave placeholders. They do not block browsing.
- ImageStore needs immutable shared cover files and persistent database references for deduplication.
- Show server trouble through the single quiet status of [0058](0058-one-quiet-server-status.md), without a notice per failed image.
- This record changes no app code, version, layout value or colour rule.
