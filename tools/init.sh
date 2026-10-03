#!/usr/bin/env bash
# Turns the template's placeholder mod into your mod: renames folders, mod ids, module paths and
# log tags from "my_mod" to <mod_name> and the display name from "My Mod" to <display name>.
# Run once, right after creating a repository from the template.
#
# Usage: tools/init.sh <mod_name> "<Display Name>"
#   mod_name: lowercase letters, digits and underscores, e.g. signal_tweaks
set -euo pipefail

name="${1:-}"
display="${2:-}"
if [[ ! "$name" =~ ^[a-z][a-z0-9_]*$ ]] || [ -z "$display" ]; then
	echo "usage: $0 <mod_name> \"<Display Name>\"   (mod_name: [a-z][a-z0-9_]*)" >&2
	exit 2
fi
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
[ -d src/my_mod ] || { echo "src/my_mod not found; already initialised?" >&2; exit 1; }

move() {
	if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then git mv "$1" "$2"; else mv "$1" "$2"; fi
}

move src/my_mod/content/my_mod "src/my_mod/content/$name"
move src/my_mod "src/$name"
move spec/ingame/my_mod_testbench/content/my_mod_testbench "spec/ingame/my_mod_testbench/content/${name}_testbench"
move spec/ingame/my_mod_testbench "spec/ingame/${name}_testbench"

python3 - "$name" "$display" <<'PY'
import os, sys
name, display = sys.argv[1], sys.argv[2]
skip_dirs = {".git", "node_modules", "vendor", "results", "dist"}
for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for file in files:
        path = os.path.join(root, file)
        if path.endswith((".png", ".zip")) or file == "init.sh":
            continue
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        updated = text.replace("my_mod", name).replace("My Mod", display)
        if updated != text:
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(updated)
            print("updated", path)
PY

tools/content_index.sh "src/$name" "spec/ingame/${name}_testbench"
echo
echo "Initialised $name (\"$display\"). Next: make deps && make lint test"
