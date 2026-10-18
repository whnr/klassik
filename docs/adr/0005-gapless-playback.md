# 0005. Gapless playback with AVAudioEngine and the MP3 header

Date: 2026-10-17. Decided by Flo after an A/B test on the phone (0.2.0). Bead: sz-rs30.1.4.

## Context

Movements that run into each other (attacca) make any gap audible. An MP3 file starts with encoder delay and ends with padding. The Xing/Info frame with the LAME extension records both. Measured on iOS 26: AVAudioFile, AVURLAsset and AudioFile ignore this header. The decoder removes only its own 529-sample delay. AVQueuePlayer plays about 30 ms of silence at each join.

## Decision

- Klassik downloads each movement before it plays, because only a whole file gives an exact trim.
- Klassik parses the Info/LAME header itself and schedules only the valid samples on one AVAudioPlayerNode: from the encoder delay, for frames × 1152 − delay − padding samples.
- Navidrome streams the original file (`format=raw`), so the header reaches the app.

## Consequences

- The first movement starts after its download.
- Files without the header play whole, with their gaps. On music.whnr.de, 165 of 445 albums have no header.
- ffmpeg sometimes writes a padding value up to 35 samples too small. The fixture lengths avoid this.
- The test for future gapless work: Beethoven "Symphonie Nr.5", track 3 into 4.
- FLAC is not tested yet (sz-rs30.1.29).
