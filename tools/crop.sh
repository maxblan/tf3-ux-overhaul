#!/usr/bin/env bash
# Crops a region out of a PNG (for reviewing in-game screenshots).
# Usage: tools/crop.sh <in.png> <out.png> <x> <y> <width> <height> [<out width> <out height>]
# With an output size the region is scaled to it (e.g. 1920 1080 for the mod preview).
set -euo pipefail
in="$(wslpath -w "$(realpath "$1")")"
touch "$2"; out="$(wslpath -w "$(realpath "$2")")"
ow="${7:-$5}"; oh="${8:-$6}"
powershell.exe -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.Drawing; \$i=[System.Drawing.Image]::FromFile('$in'); \$b=New-Object System.Drawing.Bitmap $ow,$oh; \$g=[System.Drawing.Graphics]::FromImage(\$b); \$g.InterpolationMode='HighQualityBicubic'; \$g.DrawImage(\$i,(New-Object System.Drawing.Rectangle 0,0,$ow,$oh),(New-Object System.Drawing.Rectangle $3,$4,$5,$6),[System.Drawing.GraphicsUnit]::Pixel); \$b.Save('$out'); \$i.Dispose()" < /dev/null
