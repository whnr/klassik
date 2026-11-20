#!/usr/bin/env bash
# Runs the unit, library sync and gapless tests against a running fixture server, and the UI walk if KLASSIK_UI asks.
# KLASSIK_UI: empty or "false" skips the walk, "true" or "all" walks every area, "browse,settings" walks those areas
# (the classes in ScreensTests.swift without "Screens").
# UI_TESTS_REQUIRED: "true" makes a failed UI walk fail the script. Else the script reports the failure and passes.
# A failed build or a failed unit test always fails the script.
# Exports the screenshots, the gapless report, the time of each phase and results.txt (build, unit, ui).
# KLASSIK_PHASE: all (local default), build, unit, or ui. Test phases consume archived Build/Products.
# Usage: [KLASSIK_UI=...] [UI_TESTS_REQUIRED=...] scripts/screens.sh <output-dir>
# KLASSIK_UI_TESTS narrows a playback shard to comma-separated test methods.
# Start scripts/fixture-server.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mkdir -p "$1" && cd "$1" && pwd)
rm -rf "$out"/*.xcresult "$out/timings.txt" "$out/results.txt" "$out/"*-retries.txt "$out/"*-console.txt
required=${UI_TESTS_REQUIRED:-false}
mode=${KLASSIK_PHASE:-all}
case "$mode" in all | build | unit | ui) ;; *) echo "Unknown phase: $mode" >&2; exit 2 ;; esac
# The last line of a key holds its state, so an early exit leaves "failed" or "not run" behind.
record() { echo "$1=$2" >> "$out/results.txt"; }
record ui_areas "${KLASSIK_UI:-false}"
record ui_required "$required"
record ui_methods "${KLASSIK_UI_TESTS:-}"
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
udid=${KLASSIK_SIMULATOR_UDID:-$(scripts/simulator.sh)}
echo "Simulator: $udid"
phase simulator
# A ready simulator avoids cold destination discovery and startup contention during compilation.
if [ "$mode" != build ]; then
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularMode notSupported \
    --batteryState charged --batteryLevel 100 || echo "No status bar override: the screenshot diff shows the clock."
  phase boot
fi

# The simulator answers in two architectures; naming one spares xcodebuild the choice.
project=(-project Klassik.xcodeproj -scheme Klassik -derivedDataPath build/DerivedData)
common=("${project[@]}" -destination "platform=iOS Simulator,id=$udid,arch=arm64")
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

# Runs one group of tests into its own result bundle, so the unit tests and the UI walk each have an exit status.
# xcodebuild hands TEST_RUNNER_* variables to the test runner without the prefix.
# Simulator diagnostic archives add minutes after test execution. Result bundles keep test logs and attachments without them.
run_tests() {
  local bundle=$1
  local status=0
  shift
  TEST_RUNNER_KLASSIK_SERVER_URL=http://localhost:4533 \
  TEST_RUNNER_KLASSIK_USERNAME=fixture \
  TEST_RUNNER_KLASSIK_PASSWORD=fixture \
  xcodebuild test-without-building \
    "${common[@]}" \
    -collect-test-diagnostics never \
    -retry-tests-on-failure -test-iterations 2 -test-repetition-relaunch-enabled YES \
    "$@" \
    -resultBundlePath "$out/$bundle.xcresult" \
    | tee "$out/$bundle.log" | $formatter || status=$?
  python3 scripts/screen_report.py retries "$out/$bundle.log" > "$out/$bundle-retries.txt" || return $?
  cat "$out/$bundle-retries.txt"
  return "$status"
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

# xcbeautify prints pass and fail lines only. The console of the test process holds stack traces and runtime warnings,
# and only the result bundle keeps it.
export_console() {
  local bundle=$1
  [ -d "$out/$bundle.xcresult" ] || return 0
  xcrun xcresulttool get log --path "$out/$bundle.xcresult" --type console > "$out/$bundle-console.txt" \
    || echo "::warning::No console exported from $bundle.xcresult."
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
if [ -n "${KLASSIK_UI_TESTS:-}" ]; then
  suites=()
  IFS=, read -ra methods <<< "$KLASSIK_UI_TESTS"
  for method in "${methods[@]}"; do
    suites+=("-only-testing:KlassikUITests/PlaybackScreens/$method")
  done
fi

if [ "$mode" != unit ] && [ ${#suites[@]} -gt 0 ]; then
  # The bundle keeps the name that the workflow uploads after a failure.
  # Each runner owns one simulator, so UI automation does not compete for its resources.
  run_tests screens "${suites[@]}" -parallel-testing-enabled NO || ui=$?
  record ui "$([ $ui -eq 0 ] && echo passed || echo failed)"
  phase ui
fi

export_console unit
export_console screens
export_attachments unit
export_attachments screens
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
