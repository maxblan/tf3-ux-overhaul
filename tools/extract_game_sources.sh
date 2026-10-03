#!/usr/bin/env bash
# Extracts the game's GUI-related Lua/Teal sources, API type definitions and English strings into
# .game/ (git-ignored). The file:line references in docs/inventory/ are relative to this layout:
#   .game/game/gui/gui/...        GUI recipes (the inventory's SCR/game/gui/gui/...)
#   .game/game/{base,scripts,game_mechanics,mission_x}/...
#   .game/game/apidef/...          engine API (api/tealdef)
#   .game/game/strings_en.tsv      English UI strings (key<TAB>text)
# Re-run after every game update and diff against the previous extraction.
#
# Usage: tools/extract_game_sources.sh [game folder]
set -euo pipefail

game="${1:-/mnt/c/Program Files (x86)/Steam/steamapps/common/Transport Fever 3}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
out="$repo/.game/game"
rm -rf "$out" && mkdir -p "$out"

python3 - "$game" "$out" <<'PY'
import gettext, io, os, shutil, sys, zipfile
game, out = sys.argv[1], sys.argv[2]
archives = {"gui": "gui", "base": "base", "scripts": "scripts",
            "game_mechanics": "game_mechanics", "mission": "mission_x"}
for name, target in archives.items():
    data = bytearray(open(os.path.join(game, "base/content", name + ".zip"), "rb").read())
    data[:2] = b"PK"  # TF3 archives are ZIPs with "UG" magic
    archive = zipfile.ZipFile(io.BytesIO(bytes(data)))
    for member in archive.namelist():
        if member.endswith((".lua", ".tl", ".json")):
            archive.extract(member, os.path.join(out, target))
shutil.copytree(os.path.join(game, "api/tealdef"), os.path.join(out, "apidef"))
catalog = gettext.GNUTranslations(open(os.path.join(game, "base/strings/en/LC_MESSAGES/base.mo"), "rb"))._catalog
with open(os.path.join(out, "strings_en.tsv"), "w", encoding="utf-8") as tsv:
    for key, text in catalog.items():
        key = key[0] if isinstance(key, tuple) else key
        if key:
            tsv.write(f"{key}\t{str(text).replace(chr(10), ' ')}\n")
PY
echo "extracted to $out"
