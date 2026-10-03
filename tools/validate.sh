#!/usr/bin/env bash
# Runs the game's own mod validation (TransportFever3.exe --validate) on a mod in the staging
# area and prints the result. Writes the full report to dist/validation.json.
#
# Usage: tools/validate.sh <mod-folder-name>
# Requires: the mod deployed (make deploy), the game not running, steam_appid.txt in the game folder.
set -euo pipefail

mod="${1:?usage: $0 <mod-folder-name>}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
game_dir_win='C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3'
report="$repo/dist/validation.json"

mkdir -p "$repo/dist"
rm -f "$report"
powershell.exe -NoProfile -NonInteractive -Command \
	"Start-Process -FilePath '$game_dir_win\\TransportFever3.exe' -WorkingDirectory '$game_dir_win' -ArgumentList '--validate','StagingArea,$mod','$(wslpath -w "$report")' -Wait" \
	< /dev/null

[ -f "$report" ] || { echo "validation produced no report" >&2; exit 1; }
python3 - "$report" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
print(f"validation of {report['modId']['name']}: PC {report['levelPc']}, console {report['levelConsole']}")
for message in report.get("messages") or []:
    print("  ", message)
sys.exit(1 if report["criticalPc"] or report["criticalConsole"] else 0)
PY
