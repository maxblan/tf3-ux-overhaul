#!/usr/bin/env bash
# Builds the mod.io gallery: composes the cards (compose.py) from the gallery screenshots and renders
# them to 1920 x 1080 PNGs, the gallery images src/ui_overhaul/_metadata/1.png ... 14.png. Take the screenshots first (English, this mod only):
#   spec/ingame/run.sh --save "<savegame>" --gallery --language en
#   spec/ingame/run.sh --save "<savegame>" --gallery --language en --vanilla
# The cards use Lato, the game's UI font, read from the game's locale.zip (not kept in the repo).
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
shots="$repo/spec/ingame/results"
out="$repo/src/ui_overhaul/_metadata" # the cards, as the mod's gallery images 1.png ... (0.png is the logo)
work="$repo/dist/gallery" # fonts and the composed SVGs
game_dir="/mnt/c/Program Files (x86)/Steam/steamapps/common/Transport Fever 3"
node="/mnt/c/Program Files/nodejs/node.exe"

for d in gallery-mod gallery-vanilla; do
	[ -d "$shots/$d" ] || { echo "missing $shots/$d: take the gallery screenshots first" >&2; exit 1; }
done
[ -d "$repo/tools/preview/node_modules" ] || { echo "run 'make deps' first (resvg)" >&2; exit 1; }

mkdir -p "$out" "$work/fonts" "$work/svg"
python3 - "$game_dir/base/content/locale.zip" "$work/fonts" <<'EOF'
import sys, zipfile, os
archive, target = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as z:
    for name in ("Lato-Regular.ttf", "Lato-Bold.ttf"):
        path = os.path.join(target, name)
        if not os.path.isfile(path):
            with open(path, "wb") as f:
                f.write(z.read("locale/Lato2OFL/" + name))
EOF

python3 "$repo/tools/gallery/compose.py" "$shots" "$work/svg"

# the regions the cards use, cut out once (resvg draws an image scaled past about 4096 pixels black)
mkdir -p "$shots/gallery-crops"
while read -r src crop x y w h; do
	[ -f "$shots/$crop" ] && [ "$shots/$crop" -nt "$shots/$src" ] && continue
	"$repo/tools/crop.sh" "$shots/$src" "$shots/$crop" "$x" "$y" "$w" "$h"
done < "$work/svg/crops.txt"

win() { wslpath -w "$1"; }
for svg in "$work"/svg/*.svg; do
	name="$(basename "$svg" .svg)"
	number=$((10#${name:0:2}))
	"$node" "$(win "$repo/tools/gallery/render.js")" "$(win "$svg")" "$(win "$out/$number.png")" "$(win "$shots")" \
		"$(win "$work/fonts/Lato-Regular.ttf")" "$(win "$work/fonts/Lato-Bold.ttf")"
done
echo "gallery: $out"
