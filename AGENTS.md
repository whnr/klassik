# Agents

Rules for coding agents in this repository.

## Work tracking

- Work lives in beads, in the Schaltzentrale ledger, under the epic `sz-rs30.1` with label `repo:klassik`. Reach the ledger through the `sz` connector. Use seat `code` and pass `--actor code` on every write.
- Every request, idea or aside from Flo becomes a bead under `sz-rs30.1`. Nothing lives only in chat.
- Write a decision into its bead when Flo makes it.
- Build in tracer bullets. Each slice reaches Flo's phone through TestFlight. Flo tests it before the next slice lands.
- After the pipeline works, put several beads into one push. Make one push per round of feedback.
- Push to `main`. Pull requests open later; `CONTRIBUTING.md` applies then.

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
- `.github/workflows/ci.yml` runs `scripts/lint.sh` on Linux, then `scripts/test.sh` on `macos-26` for pushes to `main` and for pull requests. Documentation changes do not start it.
- `.github/workflows/screens.yml` runs on a push to branch `screens` or by hand. It starts Navidrome on the fixture library, runs the UI tests, and uploads the screenshots as artifact `screens`. Before you report a UI change as done, fast-forward `screens`, download the artifact through the GitHub REST API, and look at every PNG.
- `.github/workflows/testflight.yml` runs by hand. It archives without signing, signs at export with the App Store Connect API key, and uploads with `altool`. A daily run uploads again when the newest build is 85 days old, because TestFlight builds expire after 90 days.
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
