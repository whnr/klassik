#!/usr/bin/env bash
# Checks the design and the Python and web code: format, lint, palettes, tokens, contrast, ADR links, specimen pages.
# Needs uv and Node. Once: uv run --with playwright==1.64.1 playwright install chromium
# `uvx ruff@0.17.3 format`, `npx prettier@3.9.10 --write` and `npx @biomejs/biome@2.6.3 lint --write` fix most findings.
set -euo pipefail
cd "$(dirname "$0")/../.."

uvx ruff@0.17.3 format --check scripts design
uvx ruff@0.17.3 check scripts design
npx --yes prettier@3.9.10 --check "design/**/*.{html,css,js,json}"
npx --yes @biomejs/biome@2.6.3 lint --error-on-warnings
uv run --no-project design/scripts/palette.py --check
uv run --no-project design/scripts/tokens.py --check
uv run --no-project design/scripts/check.py
uv run --no-project --with playwright==1.64.1 design/scripts/specimen_check.py
