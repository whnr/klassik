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

## Conversion and storage work

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
Pause cancels following automatic transfers and invalidates their decoder. Resume rebuilds from the audible checkpoint.
Shared downloads retain tracks until their last owner releases them. Their total counts physical files once.
These lifecycle checks pass in run 44916100058.

## Bounded windows and the MP3 header

[Run 44929033697](https://github.com/whnr/klassik/actions/runs/44929033697) decoded forty seconds through 1 MiB windows.
The bounded FLAC stream matched the complete file. The bounded MP3 stream matched a whole stream of the same bytes.
Both MP3 streams started 576 frames after the complete file. 576 frames is the encoder delay in the LAME header.

| Value | Early Playback MP3 |
| --- | ---: |
| Header frames × 1,152 | 114,662,016 |
| Encoder delay, padding | 576, 1,440 |
| Recording samples | 114,660,000 |
| AVAudioFile length | 114,660,000 |

iOS applied the header to this file itself and decoded only the recording.
The stream decoder assumed that iOS ignores the header, so it removed the encoder delay a second time.
That cut 13 ms of music and declared an end 576 frames after the decoder end, a premature-end failure.
The Mendelssohn fixture keeps the header untrimmed, so its stream tests did not show this.
The stream decoder now takes the decoder's own frame count, as the complete-file path does.
Both paths cut the same frames for files that iOS trims and for files that it does not trim.

## Production storage and lifecycle

TrackStore gives every automatic transfer the shared Music budget. Complete files and partial files count against the limit.
A blocked write first removes the oldest complete files. Current playback and the next opening stay.
If that makes no room, the store cancels a speculative transfer, then the next opening for current playback.
Current playback fails only when it alone fills the limit. The message tells the listener to free space.
A track larger than the limit plays from a rolling window when its format can start early.
Other oversized formats fail at their head, with a message that names the Local Storage limit.
An explicit download promotes a transfer that has not wrapped: its bytes leave the limit and the download keeps them.
A wrapped window cannot become a file, so the download then fetches the track whole.

The next opening starts when the current track has no more remaining time than the opening needs plus 2 s.
The opening time is the measured delay from engine load to first sound. Its default is 2 s.
The opening transfer holds while less than 2 s of playable audio is buffered and the current transfer is incomplete.
Playable audio is the decoded audio plus the arrived bytes that the decoder has not read, at the track's bitrate.
Decoded audio alone stays below 1.75 s, so it can never reach the 2 s floor.
Clear Music pauses playback, releases the decoders, and starts no transfer until Play or Resume, as [ADR 0060](../adr/0060-early-playback-and-read-ahead.md) records.

A queue edit keeps the sound. The engine takes the new tracks after the last one that it asked for a source.
Only an edit of a track that it already asked for loads again from the audible place.
Pause keeps the engine, unless pause cancels the transfer of the next audible track. A download keeps that transfer.

The node keeps at least two channels, so a mono opener never downmixes the stereo recordings after it.
A converted track keeps its resampler for the next track of the same source format, when that track plays from its start.
So a continuous join interpolates between real samples. Another source format first ends the carried track.

A server or network failure pauses playback and shows the one quiet server status of [the Library page](../../design/specimen/index.html); device failures keep their text.
The slow-connection line needs bytes within the last second. A server that stops sending never shows it.
A wait for bytes times out only after 30 s without any arriving byte.
A read past the arrived bytes streams one 512 KiB range after another, at most one ahead of the reader.
A range that fails without an answer retries after 0.5 s; only a whole-file or mismatched answer turns ranges off.
A reader at the bitrate, far past the arrived bytes, never waited at a range boundary with ranges at twice the bitrate.
ExtAudioFileSeek on a streamed MP3 reads the packets from the head of the file. So a seek far into an MP3 that is
still arriving waits for the sequential bytes; ranges serve the decoder only where it jumps, as at the MP3 tail.

## Throughput, seek and gain measurements

[Run 44925511145](https://github.com/whnr/klassik/actions/runs/44925511145) measured the Early Playback MP3 (320 kbit/s, 104 MB).
The feeder adds 150 ms latency, seeded jitter, and about 16 chunks per second. Each ratio ran twice; the table gives the range.

| Ratio | Target | Request to sound | Ready to render | Bytes at sound | Starvation (predicted) | Recovery |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 0.25 s | 0.72–0.82 s | 54–149 ms | 100,000–110,000 | none | — |
| 2 | 0.5 s | 1.27–1.38 s | 53–171 ms | 95,000–100,000 | none | — |
| 1 | 1.0 s | 4.13–5.36 s | 43–256 ms | 160,000–210,000 | none | — |
| 0.75 | 9.5 s | 16.2–16.7 s | 53–160 ms | 481,875–498,750 | 39.1–41.8 s (38 s) | 11.1–13.8 s |
| 0.5 | 17.0 s | 39.4–39.8 s | 102–107 ms | 785,000–795,000 | 35.4–35.8 s (34 s) | — |

Ratio 2 also restarts the throughput measurement after first sound, as a path change does. It did not starve.
Below ratio 1, starvation came after the predicted exhaustion. Decoded audio peaked at 1.70–1.75 s for every ratio.
All other buffered audio stayed encoded in the transfer. Sound came before 1 % of the resource had arrived.

A seek 1 s into a streamed MP3 or FLAC joins its next movement with zero frame shift.
The next movement keeps its exact duration. The seek start aligns within one frame of the reference.
That alignment counts from the first audible sample, so it does not resolve a single frame.
A recording join from album gain −6 dB to 0 dB changed the rendered level within 0.02 s, with zero frame shift.
The levels matched their gains within 0.5 dB.
