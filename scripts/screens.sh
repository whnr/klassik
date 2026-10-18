#!/usr/bin/env bash
# Runs the unit, UI, library sync and gapless tests against a running fixture server.
# Exports the screenshots and the gapless report.
# Usage: scripts/screens.sh <output-dir>   (start scripts/fixture-server.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mkdir -p "$1" && cd "$1" && pwd)
result="$out/screens.xcresult"
rm -rf "$result"

xcodegen generate
udid=$(scripts/simulator.sh)
echo "Simulator: $udid"
formatter=cat
command -v xcbeautify >/dev/null && formatter=xcbeautify

# xcodebuild hands TEST_RUNNER_* variables to the test runner without the prefix.
status=0
TEST_RUNNER_KLASSIK_SERVER_URL=http://localhost:4533 \
TEST_RUNNER_KLASSIK_USERNAME=fixture \
TEST_RUNNER_KLASSIK_PASSWORD=fixture \
xcodebuild test \
  -project Klassik.xcodeproj \
  -scheme Klassik \
  -destination "id=$udid" \
  -only-testing:KlassikUITests \
  -only-testing:KlassikTests \
  -resultBundlePath "$result" \
  CODE_SIGN_IDENTITY=- \
  | $formatter || status=$?

xcrun xcresulttool export attachments --path "$result" --output-path "$out/raw"
python3 scripts/name_screenshots.py "$out/raw" "$out"
exit $status
