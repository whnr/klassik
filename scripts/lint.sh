#!/usr/bin/env bash
# Checks the Swift layout against .swift-format. `swift format --in-place --recursive <dirs>` fixes most findings.
set -euo pipefail
cd "$(dirname "$0")/.."

swift format lint --strict --recursive --parallel Klassik KlassikTests KlassikUITests
