# Klassik

Klassik is a classical music player for iPhone. It plays your own library from any OpenSubsonic server. The work comes first: composer, work, recordings, movements. Albums only show where a recording came from. Your tags are the truth: Klassik reads them and never overrides them.

## Opinions

- The work is the unit. Play starts a whole work, gapless, and shuffle mixes works, not movements.
- Your tags win. MusicBrainz and Wikidata only fill gaps, such as composition dates. Klassik keeps no catalogue of its own; it links you to MusicBrainz to fix missing data there.
- Standard fields only. Klassik uses the OpenSubsonic API as specified, with no server-specific features.
- Plain iOS. Klassik uses system components and adds no design of its own.
- Classical only. Use a general Subsonic client for other music.

## Requirements

- iPhone with iOS 26 or later.
- An OpenSubsonic server. Works and movements need [Navidrome](https://www.navidrome.org) 0.63 or later and the WORK, MOVEMENTNAME, MOVEMENT and MOVEMENTTOTAL tags.

## Build

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not in the repository.

Without a Mac: push to a fork. GitHub Actions builds the app and runs the tests on a macOS runner (`.github/workflows/ci.yml`).

With a Mac and Xcode 26:

```sh
brew install xcodegen
scripts/test.sh          # generate the project, build, run the unit tests
open Klassik.xcodeproj
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
