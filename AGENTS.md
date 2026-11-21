# Agents

Rules for coding agents in this repository.

## Work tracking

- Work lives in beads, in the Schaltzentrale ledger, under the epic `sz-rs30.1` with label `repo:klassik`. Use seat `code`. Follow [ledger access](docs/agents/issue-tracker.md) for identity and actor rules.
- Every request, idea or aside from the owner becomes a bead under `sz-rs30.1`. Nothing lives only in chat.
- Write a decision into its bead when the owner makes it.
- Build in tracer bullets. Each slice reaches the tester's phone through TestFlight. The tester checks it before the next slice lands.
- After the pipeline works, put several beads into one push. Make one push per round of feedback.
- Send feature, fix, and release work through pull requests. Never promote `ci` directly to `main`.

## App rules

- SwiftUI system components: `List`, `Form`, `NavigationStack`, swipe actions, `Menu`. Style by hand only when no system component does the job.
- Layout numbers come from `Klassik/Layout.swift` and `Klassik/Tokens.swift`, never from a literal in a view.
- iOS 27 or later, Swift 6, iPhone only.
- OpenSubsonic standard fields only. No server-specific features.
- Verify behaviour against Navidrome 0.64.2. `scripts/fixture-server.sh` starts it on a generated library, on Linux or macOS.
- Credentials for a real server never go into the repository, logs or screenshots.
- The repository is public. Never commit copyrighted audio, cover art, or files from anyone's library. Test audio comes from `scripts/fixtures.py`: ffmpeg sine tones, tagged with mutagen.

## Build and ship

- `project.yml` defines the project. XcodeGen generates `Klassik.xcodeproj`; do not commit it.
- `scripts/test.sh` generates the project and runs the unit tests on an iPhone simulator.
- `scripts/lint.sh` checks the Swift layout against `.swift-format` (Swift 6.2 `swift format`). Run it before you push. `swift format --in-place --recursive Klassik KlassikTests KlassikUITests TaskRegistry` fixes most findings.
- `design/scripts/lint.sh` checks the design and all Python, HTML, CSS and JavaScript: format, lint, tokens, contrast, ADR links and the specimen pages. It needs uv and Node. Run it before you push a change to `design/`, `docs/adr/` or a Python script.
- `Klassik/Layout.swift` holds every inset, gap, corner, fixed size and text role of the views. Each value cites its specimen CSS rule. `scripts/layout_tokens.py --check` proves the citations. `scripts/layout_lint.py` refuses a literal layout number in `Klassik/`; an exception goes into `scripts/layout_literals.txt` with its reason. A specimen change that moves a value changes `Layout.swift` in the same PR. The `layout` job of `test.yml` runs both, and `design/scripts/lint.sh` runs the citation check.
- `design/scripts/tokens.py` writes `design/tokens.css`, `Klassik/Tokens.swift` and the colour sets in `Klassik/Assets.xcassets/Colors/`. Never edit them by hand. The design lint fails when one is not current. `.github/workflows/design.yml` runs it on Linux when those files change.
- `.github/workflows/test.yml` runs `scripts/lint.sh` on Linux, then unit, library sync and gapless tests on `xcode-27` with Xcode 27.2 against fixture Navidrome. It runs on `main` and `ci` pushes and pull requests, except documentation-only changes (`**.md`, `LICENSE`, `docs/**`), and manual requests. Main pushes run build, unit tests and the Release launch check, without a UI walk. Nightly runs walk all groups on main. A feature release PR titled `Release Klassik x.y.0` walks all groups. A patch release PR (`Release Klassik x.y.z`, z > 0, equal to `MARKETING_VERSION` in its `project.yml`) and other pull requests walk only requested areas. A release title without a clear x.y.z version walks all groups. The legacy `ci` branch still walks all groups. The walk uploads the screenshots as artifact `screens`.
- The walk has four groups: `playback-queue`, `playback-controls`, `places-browse` and `settings-timeline`. Both playback groups select methods from `PlaybackScreens`. Each failed test gets one retry inside its job. Reports name failed tests, count attempts, and retain first failures. Result bundles remain available after recovered retries.
- The UI walk and its screenshots take most of a run's macOS time. A pull request requests the walk with a line `[ui: <areas>]` in a commit message, such as `[ui: playback,browse]` or `[ui: all]`. The areas are the classes in `ScreensTests.swift` without `Screens`. The run walks the union of the requests in all commits of the PR, so later pushes walk the same areas. The plan warns about unknown areas and ignores them. It prints valid areas and UI group names.
- A pull request that changes the UI requests the walk for each area that it changes. Its review compares the screenshots with the specimen pages and ADRs, and checks that the PR requested the walk for the changed areas.
- A pull request that changes only logic does not request the walk. Its run starts no UI job, and the `test` check is green when the build and unit tests pass.
- The build job boots its simulator before the build and runs unit tests against the same products. Walk jobs boot during artifact setup. The Release launch check boots its simulator before building optimized products separately.
- On a run by hand, set input `ui` to the areas to walk, such as `browse,settings`, `all` (the default when the input is empty), or `false` to skip the walk. Each test of an area starts from a reset app and keeps a few screenshots. A release needs a green test run, not a passed UI walk.
- A failure of lint, fixtures, the build or a unit test always fails the run. A failed UI walk fails the `test` job only when `UI_TESTS_REQUIRED` is `true`. Set it as a repository variable, in the Actions variables of the repository settings. Without the variable the value is `false`, the default during the interface rebuild.
- A failed walk uploads `screens` and the result bundles `screens-xcresult-<group>`. The `screens-diff` job still runs. The job summary of `test` shows the build, unit and UI results, the enforcement and the missing screenshots. It shows a tolerated failure as FAILED.
- After a UI walk, job `screens-diff` compares each screenshot with the newest usable walk on the same branch, else with the newest green walk on `ci`. A walk is usable when its `screens` artifact holds screenshots. A run is never its own baseline. The job runs when screenshots exist. Differences never fail the run. Its job summary gives the baseline and the counts of new, changed, same and missing screens. Download artifact `screens-diff` through the GitHub REST API and read `diff.md`. Look at the `-diff.png` of each new or large screen. Look at a small screen only if the push changed it.
- A test run keeps the raw xcodebuild log of each test group (`unit.log`, `screens.log`) in artifact `build-report` or `walk-<group>`, and adds the console of the result bundle as `*-console.txt` when the bundle holds one. The job summary counts the lines with a crash or runtime-warning sign. The job summary of `test` gives the time of each phase: project, simulator, build, boot (the wait after the build), test, ui, export.
- `.github/workflows/testflight.yml` runs by hand. It requires a successful `test.yml` run that covers the commit. `scripts/green_test_gate.py` accepts the commit's own green run, or the newest earlier commit with a green run when every later commit changes only ignored paths (documentation, “What to Test”) and the `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` lines of `project.yml`. Any other change, also elsewhere in `project.yml`, needs its own green run. It archives without signing, signs at export with the App Store Connect API key, and uploads with `altool`. A daily run uploads again when the newest build is 85 days old, because TestFlight builds expire after 90 days.
- Write each build's “What to Test” in `docs/what-to-test.md`, with at most 4000 characters.
- Start with `Klassik X.Y.Z`, matching `MARKETING_VERSION` in `project.yml`.
- Include only numbered checks that testers perform in the installed app. Give each check an expected result and bead ID.
- Cover each app change since the last TestFlight build. Keep development instructions and process notes in PR descriptions or documentation.
- `scripts/testflight_notes.py --check` rejects version mismatches, excess length, and unambiguous development terms.
- `.github/workflows/testflight-notes.yml` runs this narrow backstop and its tests on every PR and `main` push.
- The fresh release review is the semantic gate. It checks that every instruction tests installed-app behavior.
- `testflight.yml` validates notes before its macOS job. `scripts/testflight_notes.py` sets them after upload.
- `.github/workflows/testflight-feedback.yml` runs by hand. It checks the API key secrets (`scripts/asc_check.py`), then prints TestFlight feedback and crash logs and uploads the feedback screenshots.
- Versions follow semantic versioning: `MARKETING_VERSION` in `project.yml` is MAJOR.MINOR.PATCH. In a release PR, increase MINOR for a batch with features and PATCH for a batch with only fixes. 1.0.0 is the first App Store release. The build number is the TestFlight run number. The TestFlight workflow tags each uploaded version as `vX.Y.Z`.
- Repository secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the text of the `.p8` key). Bundle ID: `de.whnr.klassik`.
- macOS runner time is expensive. Push batches, not single commits. Read CI results through the GitHub REST API. Do not poll in a tight loop.

## Releases and TestFlight

- Fix PRs never change the app version.
- `Klassik release` means one PR that bumps `MARKETING_VERSION` and adds installed-app checks in “What to Test”.
- A fresh review must approve the exact PR head before an agent merges it.
- Any head change requires a new review. Check the approved SHA against the current head before merging.
- A patch release PR (x.y.z, z > 0) requests the walk with `[ui: <areas>]` for the areas that its fixes changed. A feature release PR walks all groups.
- The release agent merges the approved release PR. When the merge commit changes only the version and “What to Test”, TestFlight reuses the green Test run of its parent and need not wait for Test on the merge commit. Otherwise it waits for successful Test on that commit.
- The release agent starts TestFlight on the merge commit and watches all jobs, including notes publication.
- Read annotations and logs. Fix failures through another reviewed PR, or report the blocker on the bead.
- Report the build, run URL, and result on the bead. The owner only installs the build and tests the app.

## Pull requests

- Push worker branches and open PRs. Never push `main` directly.
- A fresh review must approve the current PR head. A review comment must identify that SHA and its verdict.
- Agents merge approved PRs only within their assigned scope. A worker assigned to stop for review must stop.
- End every PR body with `## Test plan`: numbered on-device checks, one per app change, with expected results.
- For process-only changes, state the installed-app regression check and explain the process validation before the test plan.
- Copy the same test plan to the bead.
- A PR that changes the UI requests the walk for the changed areas (see Build and ship). Its description has a `## Screenshots` section that names the Test run of the PR head whose `screens` artifact holds the walk. It carries no inline before and after screenshots.
- Each later push that changes the UI updates the `## Screenshots` section, or adds a PR comment, with the new run and the head SHA.
- The review compares the `screens` artifact of that run with the specimen pages and ADRs. A missing inline image is not a finding.
- Report on the PR and on the bead. A bead comment alone is not enough.
- Workers do not push to the `screenshots` branch.

## Pushing

Never push main. The pre-push hook in worker checkouts refuses it.
Push your branch: `git push origin HEAD:refs/heads/<branch>`
Before pushing, check `[ui: ...]` lines in all PR commits against the areas in `scripts/screen_report.py` `UI_GROUPS`.
Then open a PR with `gh pr create`. An approved review and green CI merge it.

## Writing

- Comments state WHY, or a CONSTRAINT that the code cannot show. Never history: no "previously", "changed from", "now uses", "fixed bug where", no dates, no ticket stories. Git keeps the history.
- Commit subject: what the commit does, imperative, 50 characters or fewer. Body: why, and what it affects. No file lists, no test lists, no story of the diff. The agent that wrote the code writes the message, in the same session.
- If you do not know why, ask one question. Do not guess.
- A decision that a comment or a commit body cannot hold goes into an architecture decision record in [`docs/adr/`](docs/adr/). Write it when the owner makes the decision, and link it from the commit body. A changed decision gets a new record, and the old record points to it. Flo can instead annul a record and revive the earlier one. [`docs/adr/README.md`](docs/adr/README.md) gives the rule.
- Prose (documentation, comments, commit bodies, bead text) follows ASD-STE100 Simplified Technical English: sentences of 20 words or fewer (25 for descriptions), active voice, one meaning for each word, no hedging.
- Generated text is never longer than the thing it explains.

## Agent skills

### Issue tracker

Beads in the Schaltzentrale ledger, reached through `sz`. See `docs/agents/issue-tracker.md`.

### Triage labels

Beads labels. Two are new (`needs-triage`, `needs-info`); three already exist. See `docs/agents/triage-labels.md`.

### Prototypes

HTML prototypes that the tester tests on a phone: three variants or more, judged as a flow. See `docs/agents/prototyping.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
