#!/usr/bin/env bash
# Generates the project, builds, and runs the unit tests on an iPhone simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
udid=$(scripts/simulator.sh)
echo "Simulator: $udid"
formatter=cat
command -v xcbeautify >/dev/null && formatter=xcbeautify
xcodebuild test \
  -project Klassik.xcodeproj \
  -scheme Klassik \
  -destination "id=$udid" \
  -only-testing:KlassikTests \
  CODE_SIGNING_ALLOWED=NO \
  | $formatter
