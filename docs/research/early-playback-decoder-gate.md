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

## Remaining production work

The engine rebuilds at recording boundaries and rejects different sample rates or channel counts.
The cache lacks bounded storage for oversized tracks. Preparation and clearing still need full storage-lifecycle coverage.
The throughput matrix, path changes, and rendered joins need measurements before this feature ships.
