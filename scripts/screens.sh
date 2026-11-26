#!/usr/bin/env bash
# Runs the unit, library sync and gapless tests against a running fixture server, and the UI walk if KLASSIK_UI asks.
# KLASSIK_UI: empty or "false" skips the walk, "true" or "all" walks every area, "browse,settings" walks those areas
# (the classes in ScreensTests.swift without "Screens").
# UI_TESTS_REQUIRED: "true" makes a failed UI walk fail the script. Else the script reports the failure and passes.
# A failed build or a failed unit test always fails the script.
# Exports the screenshots, the gapless report, the time of each phase and results.txt (build, unit, ui).
# KLASSIK_PHASE: all (local default), build, unit, ui, or measure. Test phases consume archived Build/Products.
# The measure phase runs the slow throughput measurement and the wall-clock latency limits. The PR path skips them,
# because a shared runner makes elapsed time vary. The nightly run and manual runs with `measure` run them.
# A failed test is never retried, except when the simulator or runner failed (crash, lost connection, boot): then
# only the failed tests run once more, and a test that passes that way is reported as flaky.
# Usage: [KLASSIK_UI=...] [UI_TESTS_REQUIRED=...] scripts/screens.sh <output-dir>
# KLASSIK_UI_TESTS narrows a shard to comma-separated -only-testing entries: a class, or Class/method.
# Start scripts/fixture-server.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mkdir -p "$1" && cd "$1" && pwd)
rm -rf "$out"/*.xcresult "$out/timings.txt" "$out/results.txt" "$out/"*-retries.txt "$out/"*-console.txt "$out/"*-tests.json
required=${UI_TESTS_REQUIRED:-false}
mode=${KLASSIK_PHASE:-all}
case "$mode" in all | build | unit | ui | measure) ;; *) echo "Unknown phase: $mode" >&2; exit 2 ;; esac
# The last line of a key holds its state, so an early exit leaves "failed" or "not run" behind.
record() { echo "$1=$2" >> "$out/results.txt"; }
record ui_areas "${KLASSIK_UI:-false}"
record ui_required "$required"
record ui_methods "${KLASSIK_UI_TESTS:-}"
record build failed
record unit "not run"
record ui "not run"
record measure "not run"

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
# Waits for the simulator and sets the status bar. Compilation does not need a booted simulator, so a full run
# (the build job) boots in the background while it compiles and waits here only after the build.
boot() {
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularMode notSupported \
    --batteryState charged --batteryLevel 100 || echo "No status bar override: the screenshot diff shows the clock."
  phase boot
}
if [ "$mode" = all ]; then
  # An already booted simulator answers at once; a shut down one starts here, beside the compiler.
  xcrun simctl boot "$udid" 2>/dev/null || true
elif [ "$mode" != build ]; then
  boot
fi

# The simulator answers in two architectures; naming one spares xcodebuild the choice.
project=(-project Klassik.xcodeproj -scheme Klassik -derivedDataPath build/DerivedData)
common=("${project[@]}" -destination "platform=iOS Simulator,id=$udid,arch=arm64")
# Records when xcodebuild prints its first line, regenerates the SDK stat cache and starts its first compile step,
# which locates a slow start.
first_output() {
  local line seen=
  while IFS= read -r line; do
    if [ -z "$seen" ]; then
      echo "build-first-output $((SECONDS - phase_start)) s" >> "$out/timings.txt"
      seen=1
    fi
    case "$line" in
      "Base directory status changed"*) echo "build-stat-cache-regenerated $((SECONDS - phase_start)) s" >> "$out/timings.txt" ;;
      "SwiftDriver "* | "CompileC "* | "SwiftCompile "*)
        if [ "$seen" = 1 ]; then
          echo "build-first-compile $((SECONDS - phase_start)) s" >> "$out/timings.txt"
          seen=2
        fi
        ;;
    esac
    printf '%s\n' "$line"
  done
}
# The index store and the preview dylibs serve only the editor.
if [ "$mode" = all ] || [ "$mode" = build ]; then
  xcodebuild build-for-testing "${common[@]}" -showBuildTimingSummary CODE_SIGN_IDENTITY=- \
    COMPILER_INDEX_STORE_ENABLE=NO ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO \
    | tee "$out/build.log" | first_output | $formatter
  record build passed
  phase build
fi
[ "$mode" != all ] || boot
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
# Arguments: bundle name, then the -only-testing / -skip-testing selection.
# An assertion failure fails the run at once: a retry would hide a real bug. Only a failure of the simulator or the
# runner earns one more run, and only of the tests that it failed. xcodebuild runs no retry of its own.
xcodebuild_tests() {
  local bundle=$1 result=$2 append=$3
  shift 3
  local status=0
  TEST_RUNNER_KLASSIK_SERVER_URL=http://127.0.0.1:4533 \
  TEST_RUNNER_KLASSIK_USERNAME=fixture \
  TEST_RUNNER_KLASSIK_PASSWORD=fixture \
  TEST_RUNNER_KLASSIK_LATENCY_LIMITS=${KLASSIK_LATENCY_LIMITS:-0} \
  TEST_RUNNER_KLASSIK_WALK_LANGUAGE=${KLASSIK_WALK_LANGUAGE:-} \
  TEST_RUNNER_KLASSIK_CATALOG="$PWD/Klassik/Localizable.xcstrings" \
  xcodebuild test-without-building \
    "${common[@]}" \
    -collect-test-diagnostics never \
    "$@" \
    -resultBundlePath "$result" \
    | tee ${append:+"$append"} "$out/$bundle.log" | $formatter || status=$?
  return "$status"
}

# Lists the tests that the selection requests, one Class/method per line. A failure here stops the retry.
expected_tests() {
  local file=$1
  shift
  xcodebuild test-without-building "${common[@]}" "$@" -enumerate-tests -test-enumeration-style flat \
    -test-enumeration-format json -test-enumeration-output-path "$file.json" > /dev/null || return 1
  python3 scripts/screen_report.py expected-tests "$file.json" > "$file"
}

# Runs the failed and the never-run tests of a failed run once more and sets retry_status for run_tests.
# A test counts only with a passed result in the first or the retry bundle, so a run that ended early cannot pass.
# A retry that cannot be planned keeps the exit status of the first run, which run_tests passes in retry_status.
retry_tests() {
  local bundle=$1 plan="$out/$bundle-retry-plan.txt" expected="$out/$bundle-expected.txt" target
  shift
  local unplanned="::error::No retry of $bundle:"
  expected_tests "$expected" "$@" || { echo "$unplanned the requested tests are unknown."; return 0; }
  : > "$plan"
  if [ -d "$out/$bundle.xcresult" ]; then
    # An unreadable bundle may hold finished tests; a rerun of the selection would repeat them.
    xcrun xcresulttool get test-results tests --path "$out/$bundle.xcresult" > "$out/$bundle-tests.json" 2> /dev/null ||
      { echo "$unplanned the result bundle is unreadable."; return 0; }
    python3 scripts/screen_report.py retry-plan "$out/$bundle-tests.json" > "$plan" || { echo "$unplanned no plan."; return 0; }
    # Tests after an early runner exit have no result at all; the retry runs them too.
    target=$(printf '%s\n' "$@" | sed -n 's/^-only-testing:\([^/]*\).*/\1/p' | sort -u)
    case "$target" in "" | *$'\n'*) echo "$unplanned the selection has no single test target."; return 0 ;; esac
    python3 scripts/screen_report.py unrun "$expected" "$target" "$out/$bundle-tests.json" >> "$plan" ||
      { echo "$unplanned the unrun tests are unknown."; return 0; }
  else
    echo ALL > "$plan"
  fi
  [ -s "$plan" ] || return 0
  local selection=()
  if grep -qx ALL "$plan"; then
    selection=("$@")
  else
    local id arg
    while IFS= read -r id; do selection+=("-only-testing:$id"); done < <(sort -u "$plan")
    # The skip list keeps its meaning; an -only-testing entry names tests that it never excludes.
    for arg in "$@"; do case "$arg" in -skip-testing:*) selection+=("$arg") ;; esac; done
  fi
  echo "::warning::Simulator or runner failure in $bundle. Running these tests once more:"
  cat "$plan"
  retry_status=0
  xcodebuild_tests "$bundle" "$out/$bundle-retry.xcresult" -a "${selection[@]}" -parallel-testing-enabled NO || retry_status=$?
  [ "$retry_status" -eq 0 ] || return 0
  retry_status=1
  local reports=("$out/$bundle-retry-tests.json") missing failures
  xcrun xcresulttool get test-results tests --path "$out/$bundle-retry.xcresult" > "${reports[0]}" ||
    { echo "::error::The retry bundle of $bundle is unreadable."; return 0; }
  [ ! -f "$out/$bundle-tests.json" ] || reports=("$out/$bundle-tests.json" "${reports[@]}")
  # An error of a check fails the run: only an empty answer is a pass.
  missing=$(python3 scripts/screen_report.py unfinished "$expected" "${reports[@]}") ||
    { echo "::error::The results of $bundle could not be checked."; return 0; }
  [ -z "$missing" ] || { echo "::error::No passed result after the retry in $bundle: $(echo $missing)"; return 0; }
  failures=$(python3 scripts/screen_report.py assertion-failures "${reports[@]:0:1}") ||
    { echo "::error::The failures of $bundle could not be read."; return 0; }
  [ -z "$failures" ] || { echo "::error::Assertion failures in $bundle: $(echo $failures)"; return 0; }
  retry_status=0
}

run_tests() {
  local bundle=$1
  local status=0
  shift
  xcodebuild_tests "$bundle" "$out/$bundle.xcresult" "" "$@" -parallel-testing-enabled NO || status=$?
  if [ "$status" -ne 0 ]; then
    retry_status=$status
    retry_tests "$bundle" "$@"
    status=$retry_status
  fi
  python3 scripts/screen_report.py retries "$out/$bundle.log" > "$out/$bundle-retries.txt" || return $?
  cat "$out/$bundle-retries.txt"
  if grep -q '^\*\*Flaky' "$out/$bundle-retries.txt"; then
    echo "::warning::Flaky test in $bundle: it failed on a simulator or runner failure and passed on the retry. File a bead."
  fi
  if grep -q '^\*\*Runner error, retried' "$out/$bundle-retries.txt"; then
    echo "::notice::Runner error in $bundle, retried: the simulator or runner failed, not a test. Not a failed test."
  fi
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
  # A bundle can hold no console. The raw xcodebuild log ($bundle.log) then stays the record, and an empty file would
  # read as a clean run.
  xcrun xcresulttool get log --path "$out/$bundle.xcresult" --type console > "$out/$bundle-console.txt" || true
  [ -s "$out/$bundle-console.txt" ] || rm -f "$out/$bundle-console.txt"
}

unit=0
if [ "$mode" = all ] || [ "$mode" = unit ]; then
  # The measurement suite takes minutes and its limits depend on the runner, so the measure phase owns it.
  run_tests unit -only-testing:KlassikTests -skip-testing:KlassikTests/EarlyPlaybackMeasurementTests || unit=$?
  record unit "$([ $unit -eq 0 ] && echo passed || echo failed)"
  phase test
fi

measure=0
if [ "$mode" = measure ]; then
  KLASSIK_LATENCY_LIMITS=1 run_tests measure -only-testing:KlassikTests/EarlyPlaybackMeasurementTests \
    -only-testing:KlassikTests/EarlyPlaybackTests -only-testing:KlassikTests/TrackTransferTests \
    -only-testing:KlassikTests/PortraitProgressTests -only-testing:KlassikTests/StreamingPlaybackTests || measure=$?
  record measure "$([ $measure -eq 0 ] && echo passed || echo failed)"
  phase measure
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
  IFS=, read -ra entries <<< "$KLASSIK_UI_TESTS"
  for entry in "${entries[@]}"; do
    suites+=("-only-testing:KlassikUITests/$entry")
  done
fi

if [ "$mode" != unit ] && [ "$mode" != measure ] && [ ${#suites[@]} -gt 0 ]; then
  # The bundle keeps the name that the workflow uploads after a failure.
  # Each runner owns one simulator, so UI automation does not compete for its resources.
  run_tests screens "${suites[@]}" || ui=$?
  record ui "$([ $ui -eq 0 ] && echo passed || echo failed)"
  phase ui
fi

for bundle in unit measure screens; do
  export_console "$bundle"
  export_attachments "$bundle"
  # Attachments of the retried tests overwrite the failed attempt's names.
  export_attachments "$bundle-retry"
done
phase export

if [ $unit -ne 0 ]; then
  echo "::error::Unit tests failed."
  exit $unit
fi
if [ $measure -ne 0 ]; then
  echo "::error::Measurement tests failed."
  exit $measure
fi
if [ $ui -ne 0 ]; then
  if [ "$required" = true ]; then
    echo "::error::UI tests failed, and UI_TESTS_REQUIRED is true."
    exit $ui
  fi
  echo "::warning::UI tests failed. UI_TESTS_REQUIRED is not true, so the run goes on. The screenshots can be incomplete."
fi
