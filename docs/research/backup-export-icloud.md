# Export, import, backup and iCloud for listener data

This research belongs to the work on device data backup. Two parts feed it: the device backup and the notes of one recording. No app code and no ADR change. This file feeds a decision by Flo.

## Question

How does Klassik export and import the listening notes of one recording, back up all device data, and use iCloud for backup now and sync later with an iPad version? One file format must serve all three. A file never holds credentials.

## Answer

- Use one versioned JSON document, with a stable ID on every item. A notes export is the same document with only the notes section. Section 5 gives the shape.
- Export and import go through the system file dialogs (`fileExporter`, `fileImporter`). They need no iCloud entitlement. The listener may choose iCloud Drive as the folder, so a backup in iCloud works with no new capability.
- Import is a union: an item that is already there (same ID, else same content) stays single. A note changed on both sides needs a `modified` time. No deletion travels in a file.
- iCloud Backup of the whole device already includes Klassik's device file, settings and decision files. It excludes the caches and the downloads. It needs no work, and the app cannot see it or control it.
- For sync with an iPad, an iCloud Drive file is the smallest step that keeps "no hidden sync". CloudKit is the stronger engine and the larger rewrite. `NSUbiquitousKeyValueStore` fits a few settings only. Decide this when the iPad version starts, not now.

## 1. What Klassik stores on the device today

Read from `main` at f090418 (version 0.24.1). Klassik is iPhone only (`TARGETED_DEVICE_FAMILY: "1"` in `project.yml`). The app has no entitlements file and no iCloud capability. It uses no SwiftData, no Core Data and no CloudKit.

| Data | Where | Kept by | Restorable from the server or the web? |
| --- | --- | --- | --- |
| Listening notes, favourite works, favourite albums and artists, queued star changes, recent searches | `Application Support/listeners/<sha256 of server URL and username>.json` | `DeviceStore`, `ListenerFile` (`DeviceStore.swift`) | No. Notes, favourite works and recent searches are device only (ADR 0013). Queued stars are sent to the server once; before that, they are device only (ADR 0052). |
| Wikidata person picks, "chosen" tags, performer matches, check times | `Application Support/person-facts.json` | `PersonFactsStore` | Facts: yes, by lookup. Listener decisions (`chosen`, a pick, "None of these"): no. |
| MusicBrainz work links, rejected matches, unmatched works | `Application Support/enrichment.json` | `Enrichment` | Facts: yes. `rejected`, and links that the listener confirmed: no. |
| Library index | `Application Support/library.json` | `Library` | Yes, by sync. |
| Cover and picture lists | `Application Support/covers/*.json`; images in `Caches/pictures` and `Caches/album-art` | `CoverArt`, `ImageStore` | Yes. |
| Music cache | `Caches/tracks` | `TrackStore` | Yes. |
| Downloads and their lists | `Application Support/downloads`, `downloads.json`, `pending-downloads.json`; staging in `downloads-incoming` | `TrackStore`, `BackgroundDownloads` | Files: yes. The `downloads` folder is excluded from backup (`TrackStore.swift`, `saveManifest`). |
| Settings and small state | `UserDefaults` (`Library/Preferences`) | several types | Not restorable. Keys below. |
| Password | Keychain, service `de.whnr.klassik.server` | `CredentialStore` | Never exported. |

`UserDefaults` keys in code: `server.url`, `server.username`, `server.info` (last server answer), `accentFamily`, `timeline.side`, `chronology.position`, `library.filter.rules`, `library.rows`, `composerWorks.separatePartial`, `swipe.leading`, `swipe.trailing`, `player.tintStrength`, `player.scrobbles`, `player.volumeLeveling`, `player.showsAudioQuality`, `store.cacheLimit`, `settings.textFallback`, `showTaps`, and the playback state and scrobble queue under `<server key>` and `<server key>.scrobbles` (`PlaybackHistory`). The settings keys are settings of the listener. `server.info` is a cache. `server.url` and `server.username` name the listener's identity.

Facts that shape the file format:

- A note holds `id` (a `UUID`), `movement` (position in its recording), `at` and `end` (seconds) and `text` (`ListeningNote`, `ListeningNotes.swift`). It has no `modified` time.
- Notes are keyed by recording ID. A recording ID is `<workKey>|<albumKey>` (`WorkIndex.swift`). `workKey` is `mbid:<MusicBrainz ID>`, else `work:<composer>|<work name>`, else `album:<composer>|<albumKey>`. `albumKey` is the server's `albumId` (`ClassicalFilter.swift`). So a note key ties to the server's album ID. Another server, or a re-scanned library, gives other IDs, and the notes no longer match.
- The device file is one file for each server and user. The name is a hash, so the file does not name its owner.
- The favourite recording order is no longer stored. It follows from the stars and the rules (ADR 0013).
- `DeviceStore.load` refuses to replace a file that does not parse. Import must keep this rule.

## 2. What iCloud Backup includes and excludes today

Sources: Apple Support, "What does iCloud back up?" (support.apple.com/en-us/108770); Apple developer documentation, "Optimizing Your App's Data for iCloud Backup".

- iCloud Backup includes app data of every installed app. Data that an app keeps in iCloud Drive is stored in iCloud and is not in the backup (Apple Support, "App data").
- `tmp` and `Library/Caches` are excluded by default. Everything else in the app container is included unless the app sets `isExcludedFromBackup` (Apple developer documentation).
- Apple states that `isExcludedFromBackup` is guidance. It does not guarantee that an item never appears in a backup. A file operation can reset the value, so set it at each save.

Effect on Klassik today:

- Included: the device file, `person-facts.json`, `enrichment.json`, `library.json`, `covers/*.json`, `UserDefaults`.
- Excluded: `Caches/tracks`, `Caches/pictures`, `Caches/album-art`, and the `downloads` folder (explicit flag).
- Waste: `library.json` and the fact caches are regenerable and sit in the backup. They are small compared with audio. The decision files (`chosen`, `rejected`) sit in the same files as caches, so nothing can drop the caches without a split.
- Not verified: whether the Keychain password returns on a restore to a new device. Apple's pages read here do not say. Assume the listener signs in again.
- Limits of this route: the backup restores the whole phone only. The listener cannot see it, choose items from it, share one recording's notes, or restore to an iPad of another model line. The listener cannot check from inside Klassik that a backup exists. iCloud Backup counts against the listener's iCloud storage.

## 3. Options for iCloud, each judged

All four need a paid developer account and an App Store or TestFlight build, because they need entitlements. Klassik has none today.

### A. Device backup only (today)

- Cost: none.
- Gives a restore on a replacement phone.
- Gives no export, no import, no sync, no sharing, no visibility. It cannot meet "the listener sees the data and owns it".

### B. `NSUbiquitousKeyValueStore`

Source: Apple developer documentation, `NSUbiquitousKeyValueStore`.

- At most 1024 keys, 1 MB for all values, 1 MB for one value. A write over the limit fails.
- Apple: "Don't store personal or sensitive information in the key-value store." The system stores it unencrypted on disk.
- Needs the `com.apple.developer.ubiquity-kvstore-identifier` entitlement and App Store or TestFlight distribution.
- Syncs a key to the other devices of the same Apple account and posts `didChangeExternallyNotification`.
- Fits: a few settings (accent, timeline side, tint strength, swipe slots, row choices).
- Does not fit: notes, searches, decisions. One long note list passes 1 MB, and notes are personal text. Settings split across two stores would also split the backup.

### C. iCloud Drive document

Sources: Apple developer documentation, "Synchronizing documents in the iCloud environment", `url(forUbiquityContainerIdentifier:)`, `NSFileCoordinator`, `UIDocumentPickerViewController`.

- The app writes the one file into its ubiquity container, or the listener saves it into any iCloud Drive folder through the document picker (no entitlement for the picker route).
- With the entitlement `com.apple.developer.ubiquity-container-identifiers` and an `NSUbiquitousContainers` entry in `Info.plist`, the container's `Documents` folder shows in Files. The listener sees the file. The system updates this metadata only when the build number rises.
- Data in iCloud Drive is not in iCloud Backup (Apple Support). The file is its own backup.
- Sync is file-wide. Two devices that change the file produce a conflict that the app must merge. The import merge of section 5 does the same job, so one merge routine serves both.
- Reads and writes go through file coordination. A file may be a placeholder that is not downloaded yet.
- Fits "no hidden sync": the listener sees the file, can copy it, and can delete it.
- Cost: medium. No data model change. A coordinator, a conflict handler and an "iCloud Drive is off" state.

### D. CloudKit private database

Sources: Apple developer documentation, "Syncing model data across a person's devices" (SwiftData), "Setting Up Core Data with CloudKit", "Mirroring a Core Data store with CloudKit", `CKRecord`, `CKContainer`, `CKSyncEngine`.

Three ways in:

1. SwiftData with `ModelConfiguration(cloudKitDatabase:)`. It uses `NSPersistentCloudKitContainer` underneath.
2. Core Data with `NSPersistentCloudKitContainer`. The store must be SQLite.
3. CloudKit directly, with `CKSyncEngine`. The app persists the engine's state and supplies the changes to send.

Facts that bind Klassik:

- The device file is JSON, not SwiftData or Core Data. Routes 1 and 2 need a rewrite of `DeviceStore` and a one-time migration of existing files. Route 3 keeps the JSON file and adds a record mapping.
- CloudKit does not support unique constraints, required relationships or undefined attributes. Apple: CloudKit cannot enforce uniqueness because sync is concurrent. The merge by ID must therefore live in the app, as the note `UUID`.
- The schema is additive only after promotion to production. A record type or a field cannot be removed or changed. The format of section 5 must be right before the first release.
- The record data limit is 1 MB, assets excluded. One record for each note is far below it.
- Data in the private database counts against the listener's iCloud quota, not against the developer.
- Needs the iCloud (CloudKit) capability and the Background Modes capability with Remote notifications, so that the system can deliver change pushes.
- Core Data with CloudKit cannot use a container that other CloudKit code already uses. Pick a new container name for Klassik and keep it.
- Sync is automatic and in the background. The listener sees no file. This is the reverse of "no hidden sync", unless the app adds a visible status and a visible export.
- Fits best when many small items change on several devices at once: field-level merge, push, deletes.
- Cost: highest. Not verified here: how `CKSyncEngine` treats a conflict between two edits of one note. The app would write that rule.

### Comparison

| | A. Device backup | B. Key-value store | C. iCloud Drive file | D. CloudKit |
| --- | --- | --- | --- | --- |
| Entitlement and capability | none | yes | none for picker; yes for app container | yes, plus Remote notifications |
| Restore on new phone | yes, whole phone | settings only | yes, any device | yes |
| Sync with iPad | no | settings only | yes, whole file | yes, per item |
| Visible to the listener | no | no | yes, in Files | no, unless the app shows it |
| Holds all notes | yes | no (1 MB) | yes | yes |
| Merge rule in the app | none | none (last write wins) | yes, shared with import | yes, by ID |
| Change to today's storage | none | small | small | large (routes 1 and 2) or medium (route 3) |
| Fit with ADR 0013 and ADR 0052 | yes | partial | yes | partial: the queue and favourites move |

## 4. File routes in iOS

Sources: Apple developer documentation, `fileExporter`, `fileImporter`, `ShareLink`, `Transferable`, `UIDocumentPickerViewController`, "Synchronizing documents in the iCloud environment".

- `fileExporter` shows the system dialog. The listener picks the destination, including an iCloud Drive folder. It needs no entitlement.
- `fileImporter` returns security-scoped URLs. The app must call `startAccessingSecurityScopedResource` and later `stopAccessingSecurityScopedResource`.
- `ShareLink` with a `Transferable` file sends the file through the share sheet (mail, messages, AirDrop). It suits sharing one recording's notes.
- To open the file by a tap in Files or Mail, the app declares a document type: `CFBundleDocumentTypes` and `UTExportedTypeDeclarations` in `Info.plist`, with a type that conforms to `public.content` and `public.data`. `LSSupportsOpeningDocumentsInPlace` is for in-place edits and is not needed for import.
- `project.yml` is the source of `Info.plist`. A new type is a `project.yml` change.

## 5. One file format

### Shape

One JSON document, UTF-8. Suggested type: an exported UTI of the app, for example `de.whnr.klassik.data`, conforming to `public.json`, extension `.klassik`. The file stays readable and editable by hand. This also meets the wish for settings as JSON that an LLM can edit (a prompt text can ship beside the format).

```json
{
  "format": "de.whnr.klassik.data",
  "version": 1,
  "exported": "2026-11-27T10:00:00Z",
  "app": "0.24.1",
  "scope": "device",
  "notes": [
    {
      "id": "6F1C…",
      "recording": {
        "key": "mbid:…|album-123",
        "work": { "musicBrainz": "…", "composer": "Beethoven", "title": "Symphony No. 5" },
        "album": "Kleiber conducts Beethoven", "year": 1975,
        "performers": ["Carlos Kleiber", "Wiener Philharmoniker"],
        "movements": ["I. Allegro con brio", "II. Andante con moto"]
      },
      "movement": 0, "at": 61, "end": 74, "text": "…",
      "modified": "2026-11-20T18:00:00Z"
    }
  ],
  "favourites": { "works": [], "albums": [], "artists": [] },
  "pendingStars": [],
  "recentSearches": [],
  "decisions": { "composerPicks": {}, "performerPicks": {}, "chosen": [], "rejectedWorkMatches": [] },
  "settings": { "accentFamily": "…", "timeline.side": "…" }
}
```

Rules:

- `scope` is `notes` (one recording or one work), or `device`. The `notes` export holds only the `notes` section. The device export holds every section. One reader reads both.
- A section that is missing means "no change". An unknown key is kept and ignored, so a newer file loads in an older app.
- `version` is an integer. A reader refuses a version it does not know and shows why.
- Every note carries a description of its recording (`work`, `album`, `year`, `performers`, `movements`) beside `key`. The `key` ties to one server's album ID. The description lets another server or a re-scan find the recording again.
- The listener's identity (server URL and user name) goes into a `device` file only, as `listener`, because the device file is one file for each server and user. A `notes` file for sharing names no server and no user. Flo decides below whether the device file names them.
- `settings` lists known keys by name (section 1), values as plain JSON. It leaves out `server.info`, caches and counters.
- Never in any file: the password, tokens, the Keychain item, a URL with credentials, `server.info`. A writer builds the file from an allow list of keys. A test must fail when a key outside the list appears.

### Merge on import, no duplicates

For notes:

1. Same `id` in the app: the note is the same. If both have `modified`, the later wins. Without `modified` on one side, the app keeps its own and counts a conflict.
2. No `id` match: find the recording in the app. Order of tries: `key` equal; else MusicBrainz work ID with album, year and performers; else composer, title and album.
3. No match for the recording: keep the note in an "unplaced" list with its description. The listener sees the count and can retry after a sync. Never drop a note silently.
4. Recording found: a note with the same `movement`, `at`, `end` and `text` as an existing note is a duplicate. Skip it. A different `id` with the same content comes from a re-typed note and is the same note.
5. Add the rest with their `id`. Keep the `id`, so that a second import of the same file adds nothing.
6. Report the counts: added, skipped, conflicts, unplaced.

For favourites, searches, decisions and settings:

- Favourite works, albums and artists, `rejected` and `chosen`: set union.
- Recent searches: union by term, newest first, cut to the app's limit.
- Pending star changes: do not import. The queue belongs to one server and one moment (ADR 0052). A restore may import them only into the same server and user.
- Settings: a restore replaces. A merge import asks first, or skips settings. This is a decision below.
- The device file refuses a write when it does not load (`ListenerFile.loadError`). Import follows the same rule.

Gap that deletes cannot cross files. A deleted note comes back when an older file is imported. A note delete with `restore` exists in the app (`ListeningNotes.restore`). A tombstone (`deleted` time on an ID) fixes this. It is needed for sync (C and D) and optional for file import. Adding `modified` and an optional `deleted` to the note now keeps version 1 enough for sync later.

### What goes in a full backup

- In: notes, favourite works, albums and artists, recent searches, listener decisions (`chosen`, picks, rejected matches, confirmed links), the settings keys of section 1, the transport-neutral part of `library.filter.rules` and `library.rows`.
- Decide: pending star changes and the scrobble queue (`<key>.scrobbles`). Both are device only until sent. A restore on a new phone can send them late. Flo's note of 2026-11-21 lists pending star changes as in.
- Out: password, `server.info`, library index, covers, pictures, music cache, downloads, `store.cacheLimit` (device specific), playback position of the queue.
- Out: lyrics until they are stored on the device. The format has room: a new section.

## 6. Recommendation

Phase 1 (next minor version): the file.

1. Define the format of section 5 with `modified` on every note. Ship notes export and import for one recording with `ShareLink` and `fileImporter`. This is the notes part.
2. Ship the device export and import (the device backup part) in the same format, through `fileExporter` and `fileImporter`. The listener may save it in iCloud Drive. This gives an iCloud backup that the listener sees and owns, with no entitlement.
3. Do nothing for the passive device backup. It already includes the decision files and excludes the audio. Optionally split caches from decisions later to shrink the backup.

Phase 2 (iPad version): choose then between C and D.

- Choose C (iCloud Drive file) if the listener should keep seeing the file and data stays small. The merge routine of import is reused. Sync is slow and per file.
- Choose D (CloudKit) if edits on two devices at once are normal. Prefer `CKSyncEngine` on the existing JSON model over a rewrite to SwiftData, and only after the ID and `modified` rules are in the format.
- Use B (key-value store) at most for a few settings. Not for notes.

Trade-offs:

- Phase 1 costs no capability and no schema promotion. It is manual: nothing syncs by itself, and the listener must export.
- A file merge cannot carry deletes. This is acceptable for backup and for sharing. It is not acceptable for sync, so tombstones come before phase 2.
- Notes tie to the server's album ID today. Without the recording description in the file, an import onto another server or a re-scanned library places nothing. The description makes the file larger and exposes album and performer names to whoever gets a shared file.
- CloudKit schemas cannot shrink after promotion. A wrong first format costs more there than in a file.

## 7. Decisions for Flo

1. Do you accept the plan: file first (export, import, iCloud Drive by the document picker), sync later? Or do you want automatic iCloud sync in the first version?
2. Does a device backup file name the server and user (needed to restore pending stars and to match the device file), or only the data? A notes file for sharing names neither.
3. On a full restore, do settings replace the current ones, or does the listener choose? Do settings travel in a merge import at all?
4. Do pending star changes and the unsent scrobble queue go in the backup?
5. May a note without a match on this server wait in an "unplaced" list, or must the import refuse the whole file?
6. Does a note get a `modified` time and an optional `deleted` mark now (small change, needed for sync), or only when sync starts?
7. For the iPad version: file in iCloud Drive (C) or CloudKit (D)? This can wait until that version starts.
8. File name and type: `.klassik` with its own type, or a plain `.json` that any app opens?
9. Do you want the optional LLM prompt text for editing settings in this version, shipped with the format?

## Sources

Apple developer documentation (developer.apple.com/documentation, read through its JSON endpoint on 2026-11-27):

- Optimizing Your App's Data for iCloud Backup (`foundation/optimizing-your-app-s-data-for-icloud-backup`).
- `NSUbiquitousKeyValueStore` (`foundation/nsubiquitouskeyvaluestore`).
- Syncing model data across a person's devices (`swiftdata/syncing-model-data-across-a-persons-devices`).
- Setting Up Core Data with CloudKit (`coredata/setting-up-core-data-with-cloudkit`).
- Mirroring a Core Data store with CloudKit (`coredata/mirroring-a-core-data-store-with-cloudkit`).
- `CKRecord`, `CKContainer`, `CKSyncEngine` (`cloudkit/ckrecord`, `cloudkit/ckcontainer`, `cloudkit/cksyncengine-5sie5`).
- Synchronizing documents in the iCloud environment (`uikit/synchronizing-documents-in-the-icloud-environment`).
- `FileManager.url(forUbiquityContainerIdentifier:)`, `NSFileCoordinator`, `UIDocumentPickerViewController`.
- SwiftUI `fileExporter`, `fileImporter`, `ShareLink`, `FileDocument`; CoreTransferable `Transferable`.

Apple Support: "What does iCloud back up?" (support.apple.com/en-us/108770).

Klassik code at `main` f090418: `Klassik/DeviceStore.swift`, `ListeningNotes.swift`, `RecentSearches.swift`, `PersonFactsStore.swift`, `Enrichment.swift`, `WorkIndex.swift`, `ClassicalFilter.swift`, `CredentialStore.swift`, `TrackStore.swift`, `PlaybackHistory.swift`, `project.yml`; ADR 0013, 0051, 0052.

Not verified in a primary source: Keychain restore behaviour; `CKSyncEngine` conflict rules; the exact CloudKit private database quota numbers; whether a free developer account can use these capabilities (the SwiftData page states an active developer account with admin rights).
