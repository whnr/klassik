# Agents

Rules for coding agents in this repository.

## Work tracking

- Work lives in beads, in the Schaltzentrale ledger, under the epic `sz-rs30.1` with label `repo:klassik`. Reach the ledger through the `sz` connector. Use seat `code` and pass `--actor code` on every write.
- Every request, idea or aside from Flo becomes a bead under `sz-rs30.1`. Nothing lives only in chat.
- Write a decision into its bead when Flo makes it.
- Build in tracer bullets. Each slice reaches Flo's phone through TestFlight. Flo tests it before the next slice lands.
- After the pipeline works, put several beads into one push. Make one push per round of feedback.
- Push to branch `ci`. When `test.yml` is green there, fast-forward `main` to the same commit, so `main` holds only green commits. Pull requests open later; `CONTRIBUTING.md` applies then.

## App rules

- SwiftUI system components: `List`, `Form`, `NavigationStack`, swipe actions, `Menu`. Style by hand only when no system component does the job.
- iOS 26 or later, Swift 6, iPhone only.
- OpenSubsonic standard fields only. No server-specific features.
- Verify behaviour against Navidrome 0.64.2. `scripts/fixture-server.sh` starts it on a generated library, on Linux or macOS.
- Credentials for a real server never go into the repository, logs or screenshots.
- The repository is public. Never commit copyrighted audio, cover art, or files from anyone's library. Test audio comes from `scripts/fixtures.py`: ffmpeg sine tones, tagged with mutagen.

## Build and ship

- `project.yml` defines the project. XcodeGen generates `Klassik.xcodeproj`; do not commit it.
- `scripts/test.sh` generates the project and runs the unit tests on an iPhone simulator.
- `scripts/lint.sh` checks the Swift layout against `.swift-format` (Swift 6.2 `swift format`). Run it before you push. `swift format --in-place --recursive Klassik KlassikTests KlassikUITests` fixes most findings.
- `.github/workflows/test.yml` runs `scripts/lint.sh` on Linux, then the unit, library sync and gapless tests on `macos-26` against the fixture Navidrome. It runs on a push to branch `ci`, on pull requests, or by hand. A push to `main` starts no macOS run. It uploads the screenshots as artifact `screens`.
- The UI walk and its screenshots are expensive. Run them only for a UI change. Put a line `[ui]` in the newest commit message of the push to walk all areas. Put `[ui: browse,settings]` to walk only those areas, the test names in `ScreensTests` without `test`. On a run by hand, set input `ui` to `all` or to the areas. A release needs a green test run, not the UI walk.
- After a UI walk, job `screens-diff` compares each screenshot with the newest green walk on `ci`. Download artifact `screens-diff` through the GitHub REST API and read `diff.md`. Look at the `-diff.png` of each new or large screen. Look at a small screen only if the push changed it.
- The job summary of `test` gives the time of each phase: project, simulator, boot, build, test, export.
- `.github/workflows/testflight.yml` runs by hand. It refuses a commit without a green run of `test.yml`. It archives without signing, signs at export with the App Store Connect API key, and uploads with `altool`. A daily run uploads again when the newest build is 85 days old, because TestFlight builds expire after 90 days.
- Every TestFlight build has a "What to Test" text. Write it in `docs/what-to-test.md` before you release. The first line is `Klassik X.Y.Z`, the same version as in `project.yml`. Then list what changed for the listener and what Flo must test: short steps, one line each, a bead ID after each, and the known problems. At most 4000 characters. The TestFlight workflow stops before the macOS job if the version does not match, and `scripts/testflight_notes.py` sets the text on the build when the upload ends.
- `.github/workflows/testflight-feedback.yml` runs by hand. It checks the API key secrets (`scripts/asc_check.py`), then prints TestFlight feedback and crash logs and uploads the feedback screenshots.
- Versions follow semantic versioning: `MARKETING_VERSION` in `project.yml` is MAJOR.MINOR.PATCH. Increase MINOR for a batch with features and PATCH for a batch with only fixes. A fix gets its own PATCH increase, also when that version never reaches TestFlight. 1.0.0 is the first App Store release. The build number is the TestFlight run number. The TestFlight workflow tags each uploaded version as `vX.Y.Z`.
- Repository secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the text of the `.p8` key). Bundle ID: `de.whnr.klassik`.
- macOS runner time is expensive. Push batches, not single commits. Read CI results through the GitHub REST API. Do not poll in a tight loop.

## Writing

- Comments state WHY, or a CONSTRAINT that the code cannot show. Never history: no "previously", "changed from", "now uses", "fixed bug where", no dates, no ticket stories. Git keeps the history.
- Commit subject: what the commit does, imperative, 50 characters or fewer. Body: why, and what it affects. No file lists, no test lists, no story of the diff. The agent that wrote the code writes the message, in the same session.
- If you do not know why, ask one question. Do not guess.
- A decision that a comment or a commit body cannot hold goes into an architecture decision record in [`docs/adr/`](docs/adr/). Write it when Flo makes the decision, and link it from the commit body. A changed decision gets a new record.
- Prose (documentation, comments, commit bodies, bead text) follows ASD-STE100 Simplified Technical English: sentences of 20 words or fewer (25 for descriptions), active voice, one meaning for each word, no hedging.
- Generated text is never longer than the thing it explains.
