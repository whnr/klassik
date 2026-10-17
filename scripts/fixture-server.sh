#!/usr/bin/env bash
# Starts Navidrome on a generated fixture library and waits until the scan is done.
# Usage: scripts/fixture-server.sh <work-dir>
# Leaves Navidrome running on http://127.0.0.1:4533 with user "fixture", password "fixture".
# The credentials only ever exist on this throwaway server.
set -euo pipefail
cd "$(dirname "$0")/.."

version=0.64.2
work=$(mkdir -p "$1" && cd "$1" && pwd)
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m); [ "$arch" = x86_64 ] && arch=amd64; [ "$arch" = aarch64 ] && arch=arm64

if [ ! -x "$work/navidrome" ]; then
  curl -fsSL "https://github.com/navidrome/navidrome/releases/download/v$version/navidrome_${version}_${os}_${arch}.tar.gz" \
    | tar xz -C "$work" navidrome
fi
[ -d "$work/music" ] || python3 scripts/fixtures.py "$work/music"

mkdir -p "$work/data"
ND_MUSICFOLDER="$work/music" ND_DATAFOLDER="$work/data" ND_ADDRESS=127.0.0.1 ND_PORT=4533 \
  ND_LOGLEVEL=warn ND_ENABLEINSIGHTSCOLLECTOR=false \
  nohup "$work/navidrome" > "$work/navidrome.log" 2>&1 &
echo $! > "$work/navidrome.pid"

base=http://127.0.0.1:4533
for _ in $(seq 60); do curl -fs "$base/ping" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS -X POST "$base/auth/createAdmin" -H 'Content-Type: application/json' \
  -d '{"username":"fixture","password":"fixture"}' >/dev/null || true

api="$base/rest/getScanStatus.view?u=fixture&p=fixture&v=1.16.1&c=fixtures&f=json"
for _ in $(seq 60); do
  status=$(curl -fsS "$api" | python3 -c 'import json,sys; s=json.load(sys.stdin)["subsonic-response"]["scanStatus"]; print(s["scanning"], s.get("count", 0))')
  [ "${status%% *}" = False ] && [ "${status##* }" != 0 ] && break
  sleep 1
done
echo "Navidrome $version on $base: $status (scanning, tracks)"
