#!/usr/bin/env bash
# Prints the UDID of a plain iPhone simulator, such as "iPhone 17", on the newest iOS runtime that has one.
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]

def version(runtime):
    # A runtime key can end in a device family, such as "iOS-27-2-iPhone19". Only the numbers are the version.
    return [int(p) for p in runtime.rsplit("iOS-", 1)[1].split("-") if p.isdigit()]

def plain(name):
    # A plain model keeps the screenshots comparable. A fold has another screen shape and another layout.
    if re.fullmatch(r"iPhone \d+", name): return 2
    if re.match(r"iPhone \d+", name): return 1
    return 0

found = [
    (plain(d["name"]), version(runtime), d["name"], d["udid"])
    for runtime in devices if "iOS-" in runtime
    for d in devices[runtime] if d["name"].startswith("iPhone")
]
if not found:
    sys.exit("no iPhone simulator found")
_, _, name, udid = max(found)
print(name, file=sys.stderr)
print(udid)
'
