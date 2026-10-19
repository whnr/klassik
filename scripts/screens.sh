#!/usr/bin/env bash
# Runs the unit, library sync and gapless tests against a running fixture server, and the UI walk if KLASSIK_UI asks.
# KLASSIK_UI: empty or "false" skips the walk, "true" or "all" walks every area, "browse,settings" walks those areas
# (the test names in ScreensTests without "test").
# Exports the screenshots, the gapless report and the time of each phase.
# Usage: [KLASSIK_UI=...] scripts/screens.sh <output-dir>   (start scripts/fixture-server.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mkdir -p "$1" && cd "$1" && pwd)
result="$out/screens.xcresult"
rm -rf "$result" "$out/timings.txt"

# Without this, xcodebuild buffers its output in the pipe and the log timestamps say nothing.
export NSUnbufferedIO=YES
formatter=cat
command -v xcbeautify >/dev/null && formatter=xcbeautify
phase_start=$SECONDS
phase() {
  echo "$1 $((SECONDS - phase_start)) s" | tee -a "$out/timings.txt"
  phase_start=$SECONDS
}

xcodegen generate
phase project
udid=$(scripts/simulator.sh)
echo "Simulator: $udid"
phase simulator
# The first boot of a simulator takes about 3 minutes, so it runs during the build. CI starts it even earlier.
(
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # A fixed status bar keeps the clock out of the screenshot diff.
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularMode notSupported \
    --batteryState charged --batteryLevel 100 || echo "No status bar override: the screenshot diff shows the clock."
) &
boot=$!

# The simulator answers in two architectures; naming one spares xcodebuild the choice.
common=(-project Klassik.xcodeproj -scheme Klassik -destination "platform=iOS Simulator,id=$udid,arch=arm64"
  -derivedDataPath build/DerivedData)
# The index store serves only the editor.
xcodebuild build-for-testing "${common[@]}" -showBuildTimingSummary COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGN_IDENTITY=- \
  | $formatter
phase build
wait $boot
phase boot

# xcodebuild hands TEST_RUNNER_* variables to the test runner without the prefix.
suites=(-only-testing:KlassikTests)
case "${KLASSIK_UI:-false}" in
  false | "") ;;
  true | all) suites+=(-only-testing:KlassikUITests) ;;
  *)
    IFS=, read -ra areas <<< "$KLASSIK_UI"
    for area in "${areas[@]}"; do
      area=$(echo "$area" | tr -d ' ')
      first=$(echo "${area:0:1}" | tr '[:lower:]' '[:upper:]')
      suites+=("-only-testing:KlassikUITests/ScreensTests/test$first${area:1}")
    done
    ;;
esac

status=0
TEST_RUNNER_KLASSIK_SERVER_URL=http://localhost:4533 \
TEST_RUNNER_KLASSIK_USERNAME=fixture \
TEST_RUNNER_KLASSIK_PASSWORD=fixture \
xcodebuild test-without-building \
  "${common[@]}" \
  "${suites[@]}" \
  -resultBundlePath "$result" \
  | $formatter || status=$?
phase test

xcrun xcresulttool export attachments --path "$result" --output-path "$out/raw"
python3 scripts/name_screenshots.py "$out/raw" "$out"
phase export
exit $status
