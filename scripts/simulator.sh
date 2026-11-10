#!/usr/bin/env bash
# Prints the UDID of an iPhone simulator on the newest installed iOS runtime.
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]

def version(runtime):
    # A runtime key can end in a device family, such as "iOS-27-2-iPhone19". Only the numbers are the version.
    return [int(p) for p in runtime.rsplit("iOS-", 1)[1].split("-") if p.isdigit()]

def rank(name):
    # A plain model such as "iPhone 17" keeps the screenshots comparable. A fold has another screen shape.
    if re.fullmatch(r"iPhone \d+", name): return 0
    if re.match(r"iPhone \d+", name): return 1
    return 2

found = [
    (version(runtime), -rank(d["name"]), d["udid"])
    for runtime in devices if "iOS-" in runtime
    for d in devices[runtime] if d["name"].startswith("iPhone")
]
if not found:
    sys.exit("no iPhone simulator found")
newest = max(v for v, _, _ in found)
print(max((r, u) for v, r, u in found if v == newest)[1])
'
