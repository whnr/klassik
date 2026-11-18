#!/usr/bin/env bash
# CI can prepare fixtures and build products while the simulator boots.
set -euo pipefail
udid=$(scripts/simulator.sh)
echo "KLASSIK_SIMULATOR_UDID=$udid" >> "$GITHUB_ENV"
nohup xcrun simctl bootstatus "$udid" -b > "$RUNNER_TEMP/simulator-boot.log" 2>&1 &
