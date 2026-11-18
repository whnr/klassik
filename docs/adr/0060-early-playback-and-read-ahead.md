# 0060. Start playback early and read ahead quietly

Date: 2026-11-18. Proposal for Flo. Beads: sz-rs30.1.125, sz-rs30.1.125.1, sz-rs30.1.125.2 and sz-rs30.1.125.3.
Replaces the complete-file requirement of [0005](0005-gapless-playback.md) and the availability marks of [0008](0008-offline-storage.md).
Extends the music cache rules of [0051](0051-pictures-and-album-art-in-local-storage.md).
The technical choices and open questions below await approval. This record changes no app behavior.

## Context

Flo requires playback from the first useful bytes, with gapless joins intact, including large lossless files.
Low Data Mode prepares only the next track, including the first track of the next queued recording.
Normal mode prepares the current recording and that next track. Rows and the player must hide cache and loading activity.
The standing instant-app rule excludes music from library-wide preloading. Explicit downloads remain separate.

`TrackStore.file` waits for a complete URLSession download. `GaplessEngine` then opens an AVAudioFile and schedules its playable range.
Its loop loads every remaining movement, regardless of data mode. `PlaybackSession` rebuilds the engine between queue items.
It does not prepare the next recording before that transition. Its loading flag also describes inaudible background preparation.

[0005](0005-gapless-playback.md) records measured MP3 delay handling. Existing fixture tests cover complete MP3 and FLAC files.
Bead sz-rs30.1.43 records Flo's successful FLAC listening test. It leaves AAC and ALAC verification open.
Neither result proves partial-file decoding. Implementation must establish that separately on iOS 27.

## Decision

### One audio path, with a partial byte store

Keep AVAudioEngine, one AVAudioPlayerNode and the existing ReplayGain stage. Feed scheduled PCM buffers from a decoder worker.
Do not switch between AVPlayer and AVAudioEngine during a track or at a join.
AVQueuePlayer failed the measured MP3 join in 0005. An AVAssetResourceLoader supplies assets, rather than this engine's PCM input.

Use URLSession data tasks against the standard OpenSubsonic stream endpoint, with `format=raw`.
That value disables transcoding under the [OpenSubsonic stream specification](https://opensubsonic.netlify.app/docs/endpoints/stream/).
Write arriving bytes into an account-scoped partial file with an explicit map of available ranges.
Share that transfer between playback, read-ahead and an explicit download. Never download the same bytes for separate consumers.

The proposed decoder uses [AudioFileOpenWithCallbacks](https://developer.apple.com/documentation/audiotoolbox/audio-file-services).
Wrap its AudioFileID through [Extended Audio File Services](https://developer.apple.com/documentation/audiotoolbox/extended-audio-file-services) and read PCM on the decoder worker.
Callbacks read available bytes or request missing ranges. They wait only on that worker, with cancellation and a timeout.
Never block the render thread or main actor. Never represent an unavailable range as zeros or end-of-file.
Report the actual resource length when known. Unknown lengths require a sequential parser or the complete-file fallback.

Begin sequential delivery immediately. Request missing metadata or seek positions through HTTP Range when the server supports it.
Validate 206 responses, Content-Range, resource length and validators before joining ranges. Request identity content encoding.
A 200 response to a range request means sequential delivery; never place its bytes at the requested offset.
Discard partial bytes when the resource validator changes. Without a safe validator, restart rather than combine separate responses.
Use standard HTTP behavior only; require no Navidrome-specific endpoint.

This callback design is an implementation proposal, not proof that every system decoder starts early.
The first implementation must measure decoder reads and first PCM output with incomplete files.
If a decoder scans the whole resource, it fails that format's early-start gate.
Keep complete-file decoding as a compatibility fallback, without weakening existing gapless trims.
Do not call that fallback instant playback. Record its reason and address supported-format failures under sz-rs30.1.43.

### Format gates

| Source | Bytes required before early playback | Exact boundary rule |
| --- | --- | --- |
| MP3 with Xing/Info and LAME data | ID3 header, gapless header and initial complete audio frames | Derive valid sample count from frame count, encoder delay and padding. |
| MP3 without usable gapless data | Initial complete audio frames | Play its actual decoded samples; do not invent trims or promise removal of encoded silence. |
| Native FLAC | STREAMINFO, remaining metadata headers and initial audio frames | Use the declared sample count, checked against decoded frames. |
| ALAC or AAC in M4A/MP4 | Movie metadata, sample tables, codec configuration and initial audio packets | Apply valid packet-table or edit-list timing once; verify decoder priming behavior. |
| PCM WAV or AIFF | Format and audio-data headers, then complete sample frames | Use the audio-data frame count without encoder trimming. |
| ADTS AAC | Stream headers and initial packets | Early sound is possible; exact joins require trustworthy priming and end-padding information. |
| Other or unsupported containers | Complete file unless a tested incremental decoder exists | Retain tested full-file behavior; report unsupported decoding through the single status. |

Large ID3 tags and FLAC pictures can precede audio. Skip their payload through ranges when possible; inspect embedded art separately.
FLAC's [format overview](https://xiph.org/flac/documentation_format_overview.html) describes STREAMINFO and the metadata sequence.
Movie metadata at an M4A file's end requires a tail range, then any remaining metadata ranges.
Without range support, that file requires sequential receipt through its metadata, potentially the whole file.
A file extension alone never proves early-start or gapless support.

### Start threshold

Use playable audio duration, rather than a fixed downloaded percentage. Header and artwork bytes do not count as buffered audio.
Let `b` be estimated encoded audio bits per second, and `v` be measured delivered bits per second.
Use the greater of declared bitrate and the observed audio bitrate over the latest two decoded seconds.
Update variable-bitrate estimates as packets arrive. Before packet timing, use at least 320 kbit/s for MP3 and 512 kbit/s for AAC.
For lossless audio, initially use sample rate times channel count times bit depth. Prefer a larger declared bitrate when available.
Let `v` be the lower of the latest 250 ms delivery rate and the two-second moving average.
Include transfer stalls in those windows. Reset measurements when the network path changes.
Use the first available window for a new path. Before that, require two playable seconds, or the whole shorter track.

Let `r = v / b` and `T` be the remaining track duration in seconds.
The initial target `S`, in playable seconds, is:

```text
r >= 1:  S = min(T, max(0.25, 1 / r))
0 < r < 1: S = min(T, 2 + (1 - r) * min(T, 30))
r = 0:   wait for delivery; a complete local file needs no network estimate
```

Start when metadata, trim information and `S` seconds are ready. Require at least 250 ms of decoded PCM, unless shorter.
Decode only the current and immediate next track. Bound each PCM buffer set to two seconds; retain other audio encoded.
Recompute the target while waiting. Do not pause audible playback merely because its target increases.

| Encoded bitrate | Measured throughput | Target for a long track | Approximate audio bytes |
| --- | --- | --- | --- |
| 320 kbit/s | 1.28 Mbit/s | 0.25 s | 10 kB |
| 1 Mbit/s | 2 Mbit/s | 0.5 s | 62.5 kB |
| 1 Mbit/s | 1 Mbit/s | 1 s | 125 kB |
| 1 Mbit/s | 750 kbit/s | 9.5 s | 1.19 MB |
| 1 Mbit/s | 500 kbit/s | 17 s | 2.13 MB |

These figures exclude headers, network latency and decoder setup. They are tuning proposals, not measured launch results.
A 100 MB file on a sustainable connection must start before its download finishes.
A sustained `r < 1` eventually exhausts a bounded buffer. No threshold can guarantee continuous playback in that case.
For uninterrupted playback, the minimum initial deficit is approximately `(1 - r) * T`, before jitter allowance.
Do not silently transcode or require that full deficit by default. Start with the bounded target and permit a later wait.
After starvation, preserve the exact next sample and refill using this rule. Never skip samples to catch up.

### Read-ahead follows the actual queue

The current track always has priority. The next track means the next audible track after skips, shuffle and queue edits.
It can belong to another work. Normal mode's whole work means the selected recording's remaining movements, not alternate recordings.

| Effective mode | Automatic music preparation |
| --- | --- |
| Normal | Finish the current track, all remaining movements of its recording, and the first track of the next queued item. |
| Low Data Mode | Finish the current track and prepare exactly one following track, across recording boundaries. |
| Low Power Mode | Use the same one-following-track policy to reduce speculative work. |
| Offline or network access forbidden | Use existing downloads and cache only; start no network transfer. |

Prepare the next track to completion when bandwidth and storage permit. Decode its opening before the current track ends.
Prioritize its opening when the remaining playback time approaches its measured preparation time plus two seconds.
Do not let speculative tracks compete when the current buffer has fewer than two playable seconds.
Then fetch the next track, then the rest of the normal-mode set. Do not prepare beyond that set.
Cancel obsolete speculative requests after a queue change. Preserve valid stored bytes within the cache limit.
When paused, finish the current track only; stop speculative preparation. Stop cancels all automatic preparation.

Observe the actual constrained network path, including constrained Wi-Fi. Recompute the set immediately when data mode changes.
Low Data Mode permits the current and next track as playback work; it does not permit library-wide audio downloads.
Use URLSession's [network access controls](https://developer.apple.com/documentation/foundation/urlsessionconfiguration) to enforce applicable cellular and constrained-network restrictions.
Cellular alone does not imply Low Data Mode. An explicit cellular prohibition takes precedence over playback and read-ahead.
Any download policy that requires Wi-Fi also takes precedence for downloads. This proposal adds no data-settings screen.
Do not infer permission for bulk downloads from a Play tap. The download-everything option belongs to sz-rs30.1.124.
Keep [0059](0059-covers-and-pictures-before-pages.md)'s separate image policy, including the playing cover's Low Data Mode exception.

### Gapless scheduling continues across boundaries

Trim in decoded sample coordinates before scheduling. Calibrate decoder delay for the new path; do not trim decoder priming twice.
For MP3, parse the initial Xing/Info and LAME fields before sound starts.
Emit exactly the valid sample count and withhold trailing padding. Missing bytes never determine a track's end.
For FLAC, validate the sample count. For AAC and ALAC, test packet-table and container timing before claiming exact joins.

Schedule consecutive buffers on the same node timeline. Schedule the next opening before the previous valid sample finishes.
Keep the engine alive across recording boundaries. Advance session metadata from rendered sample positions, without rebuilding the graph.
Convert differing sample rates and channel layouts into one stable output format before scheduling.
Carry exact frame accounting through conversion; test rounding and converter latency at each join. Keep ReplayGain behavior from 0007.

Completing the download changes storage ownership only. Continue the same decoder and sample cursor across that event.
A seek uses available local bytes or prioritized ranges, then rebuilds decoding from a valid packet boundary.
Discard stale callbacks after a seek, skip or account change. Preserve pause and interruption behavior.
Insufficient network data can cause starvation, but must never add padding or lose audio at a join.
An unavailable next track pauses at the exact boundary. It cannot satisfy a gapless guarantee until data arrives.

### Music cache and downloads

Count all stored automatic audio bytes, including partial ranges, under Music in Local Storage.
Keep 0051's default 2 GB limit and least-recently-used eviction. Read-ahead does not authorize storage beyond that limit.
Evict unneeded entries first. Protect the current decoder's bytes and next opening while they remain in use.
If the preparation set cannot fit, reduce speculative storage before interrupting playback.
For a track larger than the limit, retain a rolling encoded window and bounded PCM; do not promote it as complete.
Disk-full playback uses bounded memory where possible and stops speculative writes. Show one actionable storage failure if playback cannot continue.

Only complete, validated files qualify as available offline. Partial files never appear as downloads or complete cache entries.
Publish complete cache entries atomically. Count each physical copy once and reuse cached bytes for explicit downloads.
Downloads remain persistent, outside the music limit. Publish a requested recording only when all its tracks are complete.
A failed recording download removes its new uncommitted download files, as 0008 requires.
Automatic read-ahead must never remove an explicit download.
Clear Music cancels speculative work and removes music files; active playback can retain only its bounded memory buffers.
Do not refill cleared music until another Play or Resume request. Signing out cancels all account transfers and removes their partial files.
Embedded art follows 0059 and counts under Album Art. Art extraction must not delay first sound.

### Quiet waiting UI

Select the work and update transport state immediately on Play. Ordinary startup and read-ahead show no loading indicator.
After one second without sound, show one secondary player line only when measured throughput is below the required bitrate.
Text: “Slow connection. Playback will start shortly.” Keep the line's space stable; use no spinner or percentage.
Remove it on first sound, pause, Stop or replacement of the selection. Background preparation must never restore it.
During later starvation, use the same single line with “Slow connection. Playback will continue shortly.”
A connection failure or policy restriction uses the one quiet status of [0058](0058-one-quiet-server-status.md), with its actual cause.
Do not label missing metadata, disk errors or an unreachable server as a slow connection.

Remove downloaded and cached marks from work, recording and movement rows, the player and its pill.
Remove the player's general loading spinner and row download progress. Keep explicit download actions available.
Show download progress, offline availability and storage totals only in Library or Local Storage, without changing row spacing during transfers.

## Consequences

Early playback needs a new byte-source interface; the complete-file closure cannot express readiness, ranges or cancellation.
The playback engine must accept decoded buffers and span queue items. Existing full-file joins remain the regression baseline.
Read-ahead uses more music cache in normal mode, within its limit. Low Data Mode limits speculative transfer to one track.
Unsustainable throughput, missing timing metadata and non-seekable containers place real limits on instant, gapless playback.
This proposal does not claim that an untested format satisfies those requirements.

### Measurements required before implementation ships

Use generated tones and attacca glides through fixture Navidrome 0.64.2. Keep copyrighted recordings out of fixtures and reports.

- Measure tap, request, first byte, first decodable packet, first rendered sample and download completion separately.
- Record transferred bytes at first sound, resource size, metadata bytes, throughput estimate, bitrate estimate and chosen target.
- For early-capable 100 MB fixtures at `r >= 2`, require sound before completion and within 500 ms after threshold readiness.
- Run throughput ratios 4, 2, 1, 0.75 and 0.5, with latency, jitter, stalls and path changes.
- Compare predicted buffer exhaustion with actual starvation. Count starvation duration and recovery time; never hide it as successful gapless playback.
- Render partial MP3, FLAC, AAC/M4A, ALAC/M4A, WAV and AIFF against complete-file reference output.
- Require zero inserted or missing frames at same-format joins, including seeks and partial-to-complete transitions.
- Test recording boundaries, queue edits, skips, mixed rates, channel layouts, pause, interruptions and stale callbacks.
- Test large leading artwork, absent trim metadata, tail movie metadata, unknown length, ignored ranges, changed validators and truncated responses.
- Measure decoder read ranges; reject early-start claims when initialization consumes the whole resource.
- Assert exact automatic request sets in each mode, including the next recording's first track and live mode changes.
- Measure stored bytes, peak PCM memory, duplicate requests, eviction, oversized tracks, Clear Music, disk failures and sign-out cleanup.
- Verify no routine spinner or availability mark remains. Check the delayed slow line appears and disappears at the stated events.
- Retain timing and sample reports without credentials or authenticated URLs. TestFlight listening confirms the automated boundary measurements.

## Open questions for Flo

1. Accept the bounded threshold when a connection stays slower than the audio bitrate?
   Recommended answer: Yes. Start after the calculated buffer; permit later quiet waits instead of waiting for most of the file.
2. Accept complete-file fallback when metadata or a system decoder prevents early playback?
   Recommended answer: Yes, as a documented compatibility exception. Require early MP3 and FLAC proof before shipping this feature.
3. Should Low Power Mode also prepare only one following track?
   Recommended answer: Yes. Keep current playback unchanged and reduce speculative work until Low Power Mode ends.
4. Accept the one-second delay and proposed slow-connection text, including the recovery text?
   Recommended answer: Yes. Keep ordinary startup and all background preparation invisible.
