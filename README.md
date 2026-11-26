# Klassik

Klassik is a classical music player for iPhone. It plays your own library from any OpenSubsonic server. The work comes first: composer, work, recordings, movements. Albums only show where a recording came from. Your tags are the truth: Klassik reads them and never overrides them.

## Opinions

- The work is the unit. Play starts a whole work, gapless.
- Your tags win. MusicBrainz and Wikidata only fill gaps, such as composition dates. Klassik keeps no catalogue of its own; it links you to MusicBrainz to fix missing data there.
- Standard fields only. Klassik uses the OpenSubsonic API as specified, with no server-specific features.
- Plain iOS. Klassik uses system components and adds no design of its own.
- Classical only. Use a general Subsonic client for other music.

## Requirements

- iPhone with iOS 27 or later.
- An OpenSubsonic server. Works and movements need [Navidrome](https://www.navidrome.org) 0.63 or later and the WORK, MOVEMENTNAME, MOVEMENT and MOVEMENTTOTAL tags.

## Build

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not in the repository.

Without a Mac: open a pull request from a fork. GitHub Actions builds the app and runs tests on macOS, except for documentation-only changes (`.github/workflows/test.yml`).

With a Mac and Xcode 27:

```sh
brew install xcodegen
scripts/test.sh          # generate the project, build, run the unit tests
open Klassik.xcodeproj
```

## Playback Lab library

`scripts/playback_lab.py` builds the test library of the Klassik Playback Lab and serves it. It needs [uv](https://docs.astral.sh/uv/) and ffmpeg, on Linux or macOS. Give it two FLAC 24/96 files of your own. They are movement 1 and movement 2 of the join; the repository holds no audio.

```sh
uv run --script scripts/playback_lab.py build --movement1 one.flac --movement2 two.flac --out lab-library
uv run --script scripts/playback_lab.py serve --music lab-library
```

`build` writes one album, `Playback Lab`, with one work per folder and two movements each: FLAC 24/96, 16/44.1 and 24/192, ALAC 24/96 and 16/44.1, AAC 256, MP3 with and without LAME header, WAV, AIFF, Opus, a work that changes from 96 kHz to 44.1 kHz, and two generated tones that need no source audio: `Wave 440 Hz` (pure sine at -12 dBFS, movement 1 exactly 10 s, movement 2 exactly 20 s) and `Wave Chord` (a soft A major chord with a slow swell, same lengths). Both are 24/96 WAV and phase-continuous across the split, so a click or gap at a join, seek or fade stands out. ReplayGain tags are on FLAC 24/96 and the MP3 with header. WAV and AIFF carry the same tags as the other cases in an ID3 chunk. `build` writes that chunk for WAV itself, because ffmpeg does not. Check in Navidrome that the WAV and AIFF works each show two movements.

`serve` downloads Navidrome 0.64.2 once (checksum verified), binds to this machine's home network address only and prints the URL, user `lab` and a generated password. `--password <value>` sets a fixed password instead: a first run creates the user with it, and a later run with another value changes the password of the user, so the flag always wins. The password is kept in `<work>/password.txt`. Run it on the home Wi-Fi and stop it with Ctrl-C when the test is done. `--address` overrides the bind address.

## Playback Lab app

`KlassikLab` is a second app on `KlassikEngine`: bundle id `de.whnr.klassik.lab`, name Playback Lab. It connects to the server of the Lab library, lists the works of the `Playback Lab` album as test cases, and plays them with the real engine. It shows the source format, the output rate that iOS reports and the join status in one line. A switch turns ReplayGain off, which builds the engine without its gain stage. A throttle makes the link slow or drops it for four seconds in every fourteen. It keeps no audio and no downloads; each play streams again.

## License

Apache License 2.0. See [LICENSE](LICENSE).
