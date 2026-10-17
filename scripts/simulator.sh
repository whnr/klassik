#!/usr/bin/env bash
# Prints the UDID of an iPhone simulator on the newest installed iOS runtime.
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
ios = sorted((k for k in devices if "iOS" in k), key=lambda k: [int(p) for p in k.rsplit("iOS-", 1)[1].split("-")])
for runtime in reversed(ios):
    for d in devices[runtime]:
        if d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit()
sys.exit("no iPhone simulator found")
'
