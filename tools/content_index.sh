#!/usr/bin/env bash
# Regenerates <mod>/_content.json, the list of files under <mod>/content/ that the game reads as
# the mod's content cache. Run after adding or removing content files (make deploy does).
#
# Usage: tools/content_index.sh <mod-dir>...
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: $0 <mod-dir>..." >&2; exit 2; }

for dir in "$@"; do
	python3 - "$dir" <<'PY'
import json, os, sys
mod = sys.argv[1]
content = os.path.join(mod, "content")
files = sorted(
    os.path.relpath(os.path.join(root, name), content).replace(os.sep, "/")
    for root, _, names in os.walk(content) for name in names
)
with open(os.path.join(mod, "_content.json"), "w", newline="\n") as handle:
    handle.write(json.dumps({"archives": None, "files": files}, indent=4) + "\n")
print(f"{mod}/_content.json: {len(files)} files")
PY
done
