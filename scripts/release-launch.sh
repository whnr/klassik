#!/usr/bin/env bash
# Builds the app in the Release configuration, as TestFlight gets it, and runs ReleaseLaunchTests against it.
# Start scripts/fixture-server.sh first.
# Usage: scripts/release-launch.sh <output-dir>
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mkdir -p "$1" && cd "$1" && pwd)
rm -rf "$out/release-launch.xcresult"
export NSUnbufferedIO=YES
formatter=cat
command -v xcbeautify >/dev/null && formatter=xcbeautify

xcodegen generate
udid=${KLASSIK_SIMULATOR_UDID:-$(scripts/simulator.sh)}
echo "Simulator: $udid"
project=(-project Klassik.xcodeproj -scheme KlassikRelease -derivedDataPath build/ReleaseData)
common=("${project[@]}" -destination "platform=iOS Simulator,id=$udid,arch=arm64")
xcodebuild build-for-testing "${common[@]}" \
  CODE_SIGN_IDENTITY=- COMPILER_INDEX_STORE_ENABLE=NO ENABLE_PREVIEWS=NO \
  | tee "$out/release-build.log" | $formatter
xcrun simctl bootstatus "$udid" -b > "$out/boot.log" 2>&1
# xcodebuild hands TEST_RUNNER_* variables to the test runner without the prefix.
status=0
TEST_RUNNER_KLASSIK_RELEASE_LAUNCH=1 \
TEST_RUNNER_KLASSIK_SERVER_URL=http://localhost:4533 \
TEST_RUNNER_KLASSIK_USERNAME=fixture \
TEST_RUNNER_KLASSIK_PASSWORD=fixture \
xcodebuild test-without-building "${common[@]}" \
  -only-testing:KlassikUITests/ReleaseLaunchTests \
  -collect-test-diagnostics never \
  -retry-tests-on-failure -test-iterations 2 -test-repetition-relaunch-enabled YES \
  -resultBundlePath "$out/release-launch.xcresult" \
  CODE_SIGN_IDENTITY=- COMPILER_INDEX_STORE_ENABLE=NO ENABLE_PREVIEWS=NO \
  | tee "$out/release-launch.log" | $formatter || status=$?
python3 scripts/screen_report.py retries "$out/release-launch.log" > "$out/release-launch-retries.txt"
cat "$out/release-launch-retries.txt" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
exit "$status"
