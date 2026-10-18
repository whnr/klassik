# 0007. ReplayGain in album mode

Date: 2026-10-18. Flo asked for ReplayGain; code chose the defaults. Bead: sz-rs30.1.28.

## Context

Recordings differ in loudness. Track gain makes a quiet movement as loud as a loud one, which destroys the music. OpenSubsonic returns `replayGain` with track and album gains and peaks.

## Decision

- Modes: Album (default), Track, Off.
- Each mode falls back to the other gain, then to `fallbackGain`.
- The peak limits a boost so that no sample clips.
- An AVAudioUnitEQ global gain applies the value, because the node volume cannot go above 1.

## Consequences

- On music.whnr.de, only 141 of 1,130 classical tracks have an album gain. Levelling needs a ReplayGain scan of the library.
