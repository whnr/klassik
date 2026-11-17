#!/usr/bin/env bash
# Runs the unit, library sync and gapless tests against a running fixture server, and the UI walk if KLASSIK_UI asks.
# KLASSIK_UI: empty or "false" skips the walk, "true" or "all" walks every area, "browse,settings" walks those areas
# (the classes in ScreensTests.swift without "Screens").
# UI_TESTS_REQUIRED: "true" makes a failed UI walk fail the script. Else the script reports the failure and passes.
# A failed build or a failed unit test always fails the script.
# Exports the screenshots, the gapless report, the time of each phase and results.txt (build, unit, ui).
# KLASSIK_PHASE: all (local default), build, unit, or ui. Test phases consume archived Build/Products.
# Usage: [KLASSIK_UI=...] [UI_TESTS_REQUIRED=...] scripts/screens.sh <output-dir>
# Start scripts/fixture-server.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mkdir -p "$1" && cd "$1" && pwd)
rm -rf "$out"/*.xcresult "$out/timings.txt" "$out/results.txt" "$out/retries.txt" "$out/retry-warnings.txt"
required=${UI_TESTS_REQUIRED:-false}
mode=${KLASSIK_PHASE:-all}
case "$mode" in all | build | unit | ui) ;; *) echo "Unknown phase: $mode" >&2; exit 2 ;; esac
# The last line of a key holds its state, so an early exit leaves "failed" or "not run" behind.
record() { echo "$1=$2" >> "$out/results.txt"; }
record ui_areas "${KLASSIK_UI:-false}"
record ui_required "$required"
record build failed
record unit "not run"
record ui "not run"

# Without this, xcodebuild buffers its output in the pipe and the log timestamps say nothing.
export NSUnbufferedIO=YES
formatter=cat
command -v xcbeautify >/dev/null && formatter=xcbeautify
phase_start=$SECONDS
phase() {
  echo "$1 $((SECONDS - phase_start)) s" | tee -a "$out/timings.txt"
  phase_start=$SECONDS
}

# A narrowed walk can leave a UI group empty; it needs no simulator.
if [ "$mode" = ui ] && { [ -z "${KLASSIK_UI:-}" ] || [ "$KLASSIK_UI" = false ]; }; then
  record build passed
  phase skipped
  exit 0
fi

if [ "$mode" = all ] || [ "$mode" = build ]; then
  xcodegen generate
fi
phase project
udid=$(scripts/simulator.sh)
echo "Simulator: $udid"
phase simulator
# The first boot of a simulator takes about 3 minutes, so it runs during the build. An earlier start slows the
# other CI steps, because the boot takes the whole runner.
if [ "$mode" != build ]; then
  (
    xcrun simctl bootstatus "$udid" -b >/dev/null
    # A fixed status bar keeps the clock out of the screenshot diff.
    xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularMode notSupported \
      --batteryState charged --batteryLevel 100 || echo "No status bar override: the screenshot diff shows the clock."
  ) &
  boot=$!
fi

# The simulator answers in two architectures; naming one spares xcodebuild the choice.
common=(-project Klassik.xcodeproj -scheme Klassik -destination "platform=iOS Simulator,id=$udid,arch=arm64"
  -derivedDataPath build/DerivedData)
# The index store and the preview dylibs serve only the editor.
if [ "$mode" = all ] || [ "$mode" = build ]; then
  xcodebuild build-for-testing "${common[@]}" -showBuildTimingSummary CODE_SIGN_IDENTITY=- \
    COMPILER_INDEX_STORE_ENABLE=NO ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO \
    | tee "$out/build.log" | $formatter
  record build passed
  phase build
fi
[ "$mode" != build ] || exit 0
if [ "$mode" != all ]; then
  # Test products use __TESTROOT__, so the archive can move between runners.
  plans=(build/DerivedData/Build/Products/*.xctestrun)
  common=(-xctestrun "${plans[0]}" -destination "platform=iOS Simulator,id=$udid,arch=arm64")
  record build passed
fi
wait "$boot"
phase boot

# Runs one group of tests into its own result bundle, so the unit tests and the UI walk each have an exit status.
# xcodebuild hands TEST_RUNNER_* variables to the test runner without the prefix.
# Simulator diagnostic archives add minutes after test execution. Result bundles keep test logs and attachments without them.
run_tests() {
  local bundle=$1
  shift
  TEST_RUNNER_KLASSIK_SERVER_URL=http://localhost:4533 \
  TEST_RUNNER_KLASSIK_USERNAME=fixture \
  TEST_RUNNER_KLASSIK_PASSWORD=fixture \
  xcodebuild test-without-building \
    "${common[@]}" \
    -collect-test-diagnostics never \
    "$@" \
    -resultBundlePath "$out/$bundle.xcresult" \
    | tee "$out/$bundle.log" | $formatter
}

# A failed test run still holds its attachments. A run that never started holds none.
export_attachments() {
  local bundle=$1
  [ -d "$out/$bundle.xcresult" ] || return 0
  rm -rf "$out/raw-$bundle"
  if xcrun xcresulttool export attachments --path "$out/$bundle.xcresult" --output-path "$out/raw-$bundle"; then
    python3 scripts/name_screenshots.py "$out/raw-$bundle" "$out"
  else
    echo "::warning::No attachments exported from $bundle.xcresult."
  fi
}

unit=0
if [ "$mode" = all ] || [ "$mode" = unit ]; then
  run_tests unit -only-testing:KlassikTests -parallel-testing-enabled NO || unit=$?
  record unit "$([ $unit -eq 0 ] && echo passed || echo failed)"
  phase test
fi

ui=0
suites=()
case "${KLASSIK_UI:-false}" in
  false | "") ;;
  true | all) suites+=(-only-testing:KlassikUITests) ;;
  *)
    IFS=, read -ra areas <<< "$KLASSIK_UI"
    for area in "${areas[@]}"; do
      area=$(echo "$area" | tr -d ' ')
      first=$(echo "${area:0:1}" | tr '[:lower:]' '[:upper:]')
      suites+=("-only-testing:KlassikUITests/$first${area:1}Screens")
    done
    ;;
esac
# XCTest can keep a dead app's process state after a launch or termination failure. A new test runner clears it.
# So only the tests that failed in that way run once more, and only when no test of the run failed in another way.
# The retry writes its own bundle, so screens.xcresult keeps the first attempt.
retry_launch_failures() {
  if ! xcrun xcresulttool get test-results tests --path "$out/screens.xcresult" > "$out/screens-tests.json"; then
    echo "::warning::No retry: no test results read from screens.xcresult."
    return 0
  fi
  local plan only=() test
  plan=$(python3 scripts/screen_report.py retry-plan "$out/screens-tests.json")
  [ -n "$plan" ] || return 0
  while IFS= read -r test; do only+=("-only-testing:KlassikUITests/$test"); done <<< "$plan"
  ui=0
  run_tests screens-retry "${only[@]}" -parallel-testing-enabled NO || ui=$?
  [ $ui -eq 0 ] || return 0
  python3 scripts/screen_report.py retries "$out/screens-tests.json" "$out"
  record ui_retried "$(paste -sd, "$out/retries.txt" | sed 's/,/, /g')"
}

if [ "$mode" != unit ] && [ ${#suites[@]} -gt 0 ]; then
  # The bundle keeps the name that the workflow uploads after a failure.
  # Each runner owns one simulator, so UI automation does not compete for its resources.
  run_tests screens "${suites[@]}" -parallel-testing-enabled NO || ui=$?
  # In an "||" list, set -e would not stop a failed report inside the function.
  if [ $ui -ne 0 ]; then retry_launch_failures; fi
  record ui "$([ $ui -eq 0 ] && echo passed || echo failed)"
  phase ui
fi

export_attachments unit
export_attachments screens
# The screenshots of a passed retry replace those of the failed attempt.
export_attachments screens-retry
phase export

if [ $unit -ne 0 ]; then
  echo "::error::Unit tests failed."
  exit $unit
fi
if [ $ui -ne 0 ]; then
  if [ "$required" = true ]; then
    echo "::error::UI tests failed, and UI_TESTS_REQUIRED is true."
    exit $ui
  fi
  echo "::warning::UI tests failed. UI_TESTS_REQUIRED is not true, so the run goes on. The screenshots can be incomplete."
fi
