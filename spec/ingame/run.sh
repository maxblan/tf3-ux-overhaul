#!/usr/bin/env bash
# In-game integration test: deploys the mod and the testbench mod, launches Transport Fever 3
# with the testbench's app script, waits for the scenarios to finish and prints their results.
#
# Usage: spec/ingame/run.sh [--timeout SECONDS] [--keep-testbench] [--save NAME] [--with-mod ID ...]
#                           [--only CHECK ...]
#   --save NAME    run on a copy of the savegame NAME (without .sav) instead of a new small map. The
#                  copy is called uio_fixture; it and its autosaves are deleted afterwards.
#   --only CHECK   run only the GUI checks of that name (and the fixture facts); repeatable
#   --with-mod ID  also activate the installed mod ID (its file system name, as the game log shows it
#                  in "will be added to filesystem ID"), e.g. to check compatibility; repeatable.
# Requires: Steam running, Transport Fever 3 not running, steam_appid.txt in the game folder.
set -euo pipefail

timeout=900
keep_testbench=0
save=""
with_mods=()
only=()
while [ $# -gt 0 ]; do
	case "$1" in
		--timeout) timeout="$2"; shift 2 ;;
		--keep-testbench) keep_testbench=1; shift ;;
		--save) save="$2"; shift 2 ;;
		--with-mod) with_mods+=("$2"); shift 2 ;;
		--only) only+=("$2"); shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

mod=ui_overhaul
repo="$(cd "$(dirname "$0")/../.." && pwd)"
mod_dir="$repo/src/$mod"
testbench_dir="$repo/spec/ingame/${mod}_testbench"
results_dir="$repo/spec/ingame/results"
game_dir_win='C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3'
game_dir="$(wslpath "$game_dir_win")"
userdata="$(ls -d "/mnt/c/Program Files (x86)/Steam/userdata/"*/3493540/local | head -n 1)"
log="$userdata/crash_dump/stdout.txt"
saves="$userdata/save"
fixture_name=uio_fixture
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

remove_fixture() {
	rm -f "$saves/$fixture_name".* "$saves/autosave_$fixture_name"_*
}
fixture_save=nil
if [ -n "$save" ]; then
	[ -f "$saves/$save.sav" ] || { echo "savegame not found: $saves/$save.sav" >&2; exit 1; }
	remove_fixture
	cp "$saves/$save.sav" "$saves/$fixture_name.sav"
	[ -f "$saves/$save.jpg" ] && cp "$saves/$save.jpg" "$saves/$fixture_name.jpg"
	fixture_save="\"$fixture_name\""
	echo "running on a copy of savegame '$save' ($fixture_name)"
fi
if [ -n "$save" ] || [ ${#with_mods[@]} -gt 0 ] || [ ${#only[@]} -gt 0 ]; then
	extra=""
	for m in "${with_mods[@]}"; do extra="$extra\"$m\", "; done
	only_list=""
	for c in "${only[@]}"; do only_list="$only_list\"$c\", "; done
	staged_fixture="$userdata/staging_area/${mod}_testbench/content/${mod}_testbench/fixture.lua"
	printf -- '-- Written by spec/ingame/run.sh\nreturn { save = %s, mods = { %s}, only = { %s} }\n' "$fixture_save" "$extra" \
		"$only_list" > "$staged_fixture"
	if [ ${#with_mods[@]} -gt 0 ]; then echo "with mods: ${with_mods[*]}"; fi
fi

launched_at=$(date +%s)
shots_dir="$results_dir/shots-$(date +%Y%m%d-%H%M%S)"

# Screenshots for visual review: the testbench logs "[testbench] SHOT <name>" and holds still for a
# few seconds; this captures the primary screen (where the game runs, in front) into
# $shots_dir/<name>.png. Other monitors are left out on purpose.
capture_screen() {
	powershell.exe -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; \$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; \$bmp=New-Object System.Drawing.Bitmap \$b.Width,\$b.Height; [System.Drawing.Graphics]::FromImage(\$bmp).CopyFromScreen(\$b.Left,\$b.Top,0,0,\$bmp.Size); \$bmp.Save('$1')" < /dev/null > /dev/null 2>&1
}
watch_shots() {
	local taken=0 names
	while true; do
		if [ -f "$log" ] && [ "$(stat -c %Y "$log")" -ge "$launched_at" ]; then
			mapfile -t names < <(grep -a "\[testbench\] SHOT " "$log" | sed 's/.*SHOT //; s/[^A-Za-z0-9_.-]//g')
			while [ "$taken" -lt "${#names[@]}" ]; do
				mkdir -p "$shots_dir"
				capture_screen "$(wslpath -w "$shots_dir")\\${names[$taken]}.png"
				echo "$(date +%H:%M:%S) captured ${names[$taken]}" >> "$shots_dir/captures.txt"
				taken=$((taken + 1))
			done
		fi
		sleep 0.5
	done
}
echo "launching Transport Fever 3 with --script $app_script"
powershell.exe -NoProfile -NonInteractive -Command \
	"Start-Process -FilePath '$game_dir_win\\TransportFever3.exe' -WorkingDirectory '$game_dir_win' -ArgumentList '--script','$app_script'" \
	< /dev/null

watch_shots &
watcher=$!
# the watcher loops forever: stop it however this script ends (Ctrl-C, an error under set -e)
trap 'kill "$watcher" 2> /dev/null || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
outcome="timeout"
seen=0
missing=0
while [ $(( $(date +%s) - launched_at )) -lt "$timeout" ]; do
	sleep 5
	# stdout.txt is rewritten on startup; ignore the previous session's file.
	[ -f "$log" ] && [ "$(stat -c %Y "$log")" -ge "$launched_at" ] || continue
	if grep -aq "\[testbench\] DONE" "$log"; then outcome="done"; break; fi
	if grep -aq "Ungraceful exit\|Calling HandleCrash\|MinidumpCallback\|Possible hang detected" "$log"; then outcome="crash"; break; fi
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
kill "$watcher" 2> /dev/null || true
taskkill.exe /IM TransportFever3.exe /F < /dev/null > /dev/null 2>&1 || true

mkdir -p "$results_dir"
saved="$results_dir/$(date +%Y%m%d-%H%M%S)-stdout.txt"
[ -f "$log" ] && cp "$log" "$saved"
[ "$keep_testbench" -eq 1 ] || "$repo/tools/deploy.sh" --remove "$testbench_dir"
[ -z "$save" ] || remove_fixture

echo
echo "outcome: $outcome   (full log: $saved)"
[ -d "$shots_dir" ] && echo "screenshots: $shots_dir"
echo "--- testbench output ---"
grep -a "\[testbench\]\|\[$mod\]" "$saved" | sed 's/^\[[^]]*\]  //' || true
echo "--- engine errors ---"
# "Script component root failed": a recipe broke the GUI tree and the engine dropped the whole game UI.
# "React: ..." errors (e.g. a duplicate component id) leave the UI running but in a broken state.
gui_failures=$(grep -ac "ReactFramework::Load() failed\|Script component root failed\|\] *+\? *React: " "$saved" || true)
# A mod module that failed and fell back to vanilla logs "[ui_overhaul] disabled ..." or "... failed".
mod_failures=$(grep -ac "\[ui_overhaul\] disabled\|\[ui_overhaul\] .* failed" "$saved" || true)
grep -a -A6 "ProposalData error\|Lua error\|Error while running lua app script\|Fatal error\|ReactFramework::Load() failed\|React: " \
	"$saved" | cut -c1-300 | head -60 || true

passed=$(grep -ac "\[testbench\] PASS" "$saved" || true)
failed=$(grep -ac "\[testbench\] FAIL" "$saved" || true)
echo
echo "scenarios: $passed passed, $failed failed"
if [ "$outcome" = "crash" ]; then
	echo "--- last lines before the crash ---"
	grep -a -B12 "MinidumpCallback\|Calling HandleCrash" "$saved" | cut -c1-200 | head -14 || true
fi
[ "$gui_failures" -eq 0 ] || echo "GUI failed to load ($gui_failures times), see engine errors above"
[ "$mod_failures" -eq 0 ] || { echo "mod modules fell back to vanilla ($mod_failures lines):"; grep -a "\[ui_overhaul\] disabled\|\[ui_overhaul\] .* failed" "$saved" | cut -c1-300 | head; }
[ "$outcome" = "done" ] && [ "$failed" -eq 0 ] && [ "$passed" -gt 0 ] && [ "$gui_failures" -eq 0 ] && [ "$mod_failures" -eq 0 ]
