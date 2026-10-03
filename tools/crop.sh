#!/usr/bin/env bash
# Crops a region out of a PNG (for reviewing in-game screenshots).
# Usage: tools/crop.sh <in.png> <out.png> <x> <y> <width> <height>
set -euo pipefail
in="$(wslpath -w "$(realpath "$1")")"
touch "$2"; out="$(wslpath -w "$(realpath "$2")")"
powershell.exe -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.Drawing; \$i=[System.Drawing.Image]::FromFile('$in'); \$b=New-Object System.Drawing.Bitmap $5,$6; \$g=[System.Drawing.Graphics]::FromImage(\$b); \$g.DrawImage(\$i,(New-Object System.Drawing.Rectangle 0,0,$5,$6),(New-Object System.Drawing.Rectangle $3,$4,$5,$6),[System.Drawing.GraphicsUnit]::Pixel); \$b.Save('$out'); \$i.Dispose()" < /dev/null
