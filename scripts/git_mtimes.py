"""Sets each tracked file's modification time to the time of the last commit that changed it.

A fresh checkout gives every file the time of the checkout, so the Swift compiler rebuilds every file
even with a cached DerivedData. Needs the full history (actions/checkout with fetch-depth: 0).
Usage: python3 scripts/git_mtimes.py
"""
import os, subprocess

tracked = set(subprocess.run(["git", "ls-files", "-z"], capture_output=True, text=True, check=True).stdout.split("\0")) - {""}
log = subprocess.run(
    ["git", "log", "--format=@%ct", "--name-only", "--no-renames"], capture_output=True, text=True, check=True
).stdout
done = set()
for line in log.splitlines():
    if line.startswith("@"):
        when = int(line[1:])
    elif line in tracked and line not in done:
        os.utime(line, (when, when))
        done.add(line)
print(f"{len(done)} files set to their last commit time")
