# Early playback decoder gate

[ADR 0060](../adr/0060-early-playback-and-read-ahead.md) requires MP3 and FLAC proof before early playback ships.
[PR #104](https://github.com/whnr/klassik/pull/104) contains the probes and the unfinished production implementation.

## Decoder measurements

The iOS 27 simulator ran against generated audio through Navidrome 0.64.2.
[Run 44422173523](https://github.com/whnr/klassik/actions/runs/44422173523) retains reports in `build-report`.

| Format | Resource bytes | Bytes at open | Delivered bytes at first PCM | PCM frames | Decoder elapsed |
| --- | ---: | ---: | ---: | ---: | ---: |
| MP3 | 104,003,020 | 25,067 | 94,736 | 11,025 | 20.8 ms |
| FLAC | 111,017,069 | 36,149 | 278,173 | 11,025 | 325.0 ms |

Delivered bytes include repeated callback reads. They do not describe a network transfer rate.
Both complete-file controls returned the same first-channel samples and frame counts. Both decoder gates pass.
MP3 initialization also read four bytes at offset 104,002,892. Early MP3 therefore needs a safe metadata range.
Without a safe validator or range response, production playback uses the complete-file fallback.
FLAC initialization read its sequential prefix.
These decoder results do not prove rendered startup time, storage bounds, or joins across recording boundaries.

[Run 44865958099](https://github.com/whnr/klassik/actions/runs/44865958099) repeated both decoder gates with current main.
MP3 returned its first PCM in 12.1 ms; FLAC took 220.2 ms. Callback byte counts matched the table.
Both complete-file controls passed. The run failed when the separate render probe crashed.
The render probe requires the iOS 27 Sendable tap API; this run does not establish rendered startup time.

## Production timeline measurements

[Run 44868823497](https://github.com/whnr/klassik/actions/runs/44868823497) passed the decoder gates, rendered startup, and complete-file controls.
The production node rendered MP3 and FLAC joins across recordings with zero inserted or missing frames.
The sample map excludes starvation silence from movement position and duration. Premature decoded EOF fails instead of ending the movement.

| Format | Resource bytes | Bytes at first sound | Time from engine load to sound |
| --- | ---: | ---: | ---: |
| MP3 | 104,003,020 | 98,304 | 1,051 ms |
| FLAC | 111,017,069 | 196,608 | 344 ms |

The feeder delivered twice the initial bitrate estimate. These times include initialization and buffering.
The probe does not separate threshold readiness from first sound. It does not establish the 500 ms readiness requirement.

## Remaining production work

[Run 44892454080](https://github.com/whnr/klassik/actions/runs/44892454080) found fractional-output shortages during conversion.
The 44.1-to-48 kHz impulse produced 8,725 frames instead of 8,726.
The mixed-rate recording required 22,068 frames; conversion returned 22,067.
The conversion supplies zero input context for final interpolation, without extending the declared output length.
The following run validates its impulse, extended-reference, source-EOF, and rendered comparisons.

[Run 44916100058](https://github.com/whnr/klassik/actions/runs/44916100058) validates conversion at 99f2797.
Converter callbacks hold the converter lock. Reading `primeInfo` inside that callback caused a recursive-lock crash.
Reading it before conversion removes that crash. All 795 unit tests pass.
Fractional frame counts, chunk invariance, impulse positions, zero-extended references, and source-EOF checks pass.
Rendered mixed-format joins match their complete-file reference at frames 22,051 and 44,117.
The queue contains 44.1, 48, and 32 kHz audio, with mono and stereo tracks.
MP3 and FLAC recording joins retain zero frame shifts. Existing complete-file and seek controls also pass.

The partial-file backing retains metadata and maps a reclaimable circular window into source coordinates.
Its tests cover repeated wraps, missing ranges, download reconstruction, disk truncation, and atomic publication.
The shared budget counts complete files, partial files, and open files after deletion.
Concurrent writers cannot spend the same free bytes. Publication preserves one physical charge.
Transfers use that backing without a finite capacity. Production rolling storage remains disabled.
Finite transfers wait on their transport queue when the window or shared budget fills.
Decoder reads release storage slots. Cancellation wakes blocked writes. Reclaimed resources never publish as complete files.
The forty-second MP3 and FLAC reference probes use 1 MiB windows. Their iOS validation remains pending.
TrackStore accounting, download ownership changes, and bounded fallback must precede production finite-capacity use.

The cache lacks bounded storage for oversized tracks. Read-ahead still waits for the current transfer to finish.
Pause cancels following automatic transfers and invalidates their decoder. Resume rebuilds from the audible checkpoint.
Shared downloads retain tracks until their last owner releases them. Their total counts physical files once.
These lifecycle checks pass in run 44916100058. Clear Music needs further coverage for active decoders and refill suppression.
The throughput matrix, path changes, seeks, remaining format controls, storage pressure, and recovery still need measurements.
ReplayGain changes also need rendered coverage across recording boundaries. The current gain stage follows session metadata updates.
Passing decoder and timeline checks do not close these production requirements.
