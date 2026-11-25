# Gapless playback by format

A join is gapless when the end of one track and the start of the next play without a lost or repeated sample.
It holds inside one work's recording. The Playback Lab (`scripts/playback_lab.py`) has a case for each format.

| Format | iOS decodes | Gapless data | Engine |
|---|---|---|---|
| MP3 with LAME or Xing header | yes | delay and padding in the Info frame | `MP3GaplessInfo` cuts them; streamed early |
| MP3 without header | yes | none | plays whole; the join is approximate (ADR 0005) |
| FLAC | yes | exact count in STREAMINFO | streamed early, cut at the count |
| AAC in M4A | yes | `iTunSMPB` tag, or edit list and last short packet | `M4AGaplessInfo` cuts priming and remainder; full file first |
| ALAC in M4A | yes | the same atoms, no priming | same path; every frame is audio |
| WAV, AIFF | yes | none needed | full file first, played whole |
| Opus, Ogg Vorbis | no | pre-skip in OpusHead | not playable on iOS in Ogg; out of scope |

The system decoder already cuts an M4A file at its edit list. An ffmpeg edit list has millisecond resolution, so a track
loses at most 44 frames at its end (about one millisecond).

`M4AGaplessInfo` reads `iTunSMPB` first. Without it, the first edit's media time is the priming, and the packet
durations give the end. An edit list has the resolution of the movie time scale, so a shorter list ends the
recording only when it is shorter by more than that resolution. A decoder that already trims the file keeps
the whole file. A file with no trim data plays whole.

`scripts/format_fixtures.py` writes the short fixtures that `FormatGaplessTests` uses.
