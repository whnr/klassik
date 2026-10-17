"""Copies exported xcresult attachments to <name>.png, using the names the UI tests gave them.

Usage: python3 scripts/name_screenshots.py <export-dir> <output-dir>
"""
import json, pathlib, re, shutil, sys

raw, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
for test in json.loads((raw / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        exported = attachment["exportedFileName"]
        # Xcode appends "_<index>_<UUID>" to the attachment name.
        name = re.sub(r"_\d+_[0-9A-F-]{36}(?=\.\w+$)", "", attachment.get("suggestedHumanReadableName", exported))
        shutil.copy(raw / exported, out / name)
        print(out / name)
