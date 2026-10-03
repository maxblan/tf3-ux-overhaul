#!/usr/bin/env bash
# In-game integration test: deploys the mod and the testbench mod, launches Transport Fever 3
# with the testbench's app script, waits for the scenarios to finish and prints their results.
#
# Usage: spec/ingame/run.sh [--timeout SECONDS] [--keep-testbench]
# Requires: Steam running, Transport Fever 3 not running, steam_appid.txt in the game folder.
set -euo pipefail

timeout=900
keep_testbench=0
while [ $# -gt 0 ]; do
	case "$1" in
		--timeout) timeout="$2"; shift 2 ;;
		--keep-testbench) keep_testbench=1; shift ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

mod=ux_overhaul
repo="$(cd "$(dirname "$0")/../.." && pwd)"
mod_dir="$repo/src/$mod"
testbench_dir="$repo/spec/ingame/${mod}_testbench"
results_dir="$repo/spec/ingame/results"
game_dir_win='C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3'
game_dir="$(wslpath "$game_dir_win")"
log="$(ls -d "/mnt/c/Program Files (x86)/Steam/userdata/"*/3493540/local | head -n 1)/crash_dump/stdout.txt"
# --script takes a game resource path; the app script ships inside the testbench mod.
app_script="${mod}_testbench_1::/${mod}_testbench/app_script.lua"

game_running() {
	# Windows executables need a closed stdin when called from a background shell.
	tasklist.exe < /dev/null 2>/dev/null | grep -qi "TransportFever3.exe"
}

if game_running; then
	echo "Transport Fever 3 is running; close it first." >&2
	exit 1
fi
# Without steam_appid.txt the game relaunches through Steam, which asks to confirm the custom
# --script argument and blocks unattended runs.
if [ ! -f "$game_dir/steam_appid.txt" ]; then
	echo "Missing steam_appid.txt in the game folder. Create it once with:" >&2
	echo "  printf 3493540 > \"$game_dir/steam_appid.txt\"" >&2
	exit 1
fi

"$repo/tools/deploy.sh" "$mod_dir" "$testbench_dir"

launched_at=$(date +%s)
echo "launching Transport Fever 3 with --script $app_script"
powershell.exe -NoProfile -NonInteractive -Command \
	"Start-Process -FilePath '$game_dir_win\\TransportFever3.exe' -WorkingDirectory '$game_dir_win' -ArgumentList '--script','$app_script'" \
	< /dev/null

outcome="timeout"
seen=0
missing=0
while [ $(( $(date +%s) - launched_at )) -lt "$timeout" ]; do
	sleep 5
	# stdout.txt is rewritten on startup; ignore the previous session's file.
	[ -f "$log" ] && [ "$(stat -c %Y "$log")" -ge "$launched_at" ] || continue
	if grep -aq "\[testbench\] DONE" "$log"; then outcome="done"; break; fi
	if grep -aq "Ungraceful exit\|Calling HandleCrash" "$log"; then outcome="crash"; break; fi
	# The process only appears in tasklist some seconds after launch; count misses after that.
	if game_running; then
		seen=1
		missing=0
	elif [ "$seen" -eq 1 ]; then
		missing=$((missing + 1))
	fi
	if [ "$missing" -ge 3 ]; then outcome="exited"; break; fi
done

sleep 2
taskkill.exe /IM TransportFever3.exe /F < /dev/null > /dev/null 2>&1 || true

mkdir -p "$results_dir"
saved="$results_dir/$(date +%Y%m%d-%H%M%S)-stdout.txt"
[ -f "$log" ] && cp "$log" "$saved"
[ "$keep_testbench" -eq 1 ] || "$repo/tools/deploy.sh" --remove "$testbench_dir"

echo
echo "outcome: $outcome   (full log: $saved)"
echo "--- testbench output ---"
grep -a "\[testbench\]\|\[$mod\]" "$saved" | sed 's/^\[[^]]*\]  //' || true
echo "--- engine errors ---"
# "Script component root failed": a recipe broke the GUI tree and the engine dropped the whole game UI.
gui_failures=$(grep -ac "ReactFramework::Load() failed\|Script component root failed" "$saved" || true)
grep -a -A6 "ProposalData error\|Lua error\|Error while running lua app script\|Fatal error\|ReactFramework::Load() failed" \
	"$saved" | cut -c1-300 | head -60 || true

passed=$(grep -ac "\[testbench\] PASS" "$saved" || true)
failed=$(grep -ac "\[testbench\] FAIL" "$saved" || true)
echo
echo "scenarios: $passed passed, $failed failed"
[ "$gui_failures" -eq 0 ] || echo "GUI failed to load ($gui_failures times), see engine errors above"
[ "$outcome" = "done" ] && [ "$failed" -eq 0 ] && [ "$passed" -gt 0 ] && [ "$gui_failures" -eq 0 ]
