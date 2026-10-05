#!/usr/bin/env bash
# In-game integration test: deploys the mod and the testbench mod, launches Transport Fever 3
# with the testbench's app script, waits for the scenarios to finish and prints their results.
#
# Usage: spec/ingame/run.sh [--timeout SECONDS] [--keep-testbench] [--save NAME] [--with-mod ID ...]
#                           [--only CHECK ...] [--gallery [--vanilla]] [--language CODE]
#   --save NAME    run on a copy of the savegame NAME (without .sav) instead of a new small map. The
#                  copy is called uio_fixture; it and its autosaves are deleted afterwards.
#   --only CHECK   run only the GUI checks of that name (and the fixture facts); repeatable
#   --mods-first   put the --with-mod mods before this mod in the activation order (default: after)
#   --off FEATURE  switch that feature of the mod off in its settings (a key of gui/settings.lua, e.g.
#                  terminals); repeatable. The GUI checks expect that part vanilla.
#   --with-mod ID  also activate the installed mod ID (its file system name, as the game log shows it
#                  in "will be added to filesystem ID"), e.g. to check compatibility; repeatable.
#   --gallery      shoot the gallery scenes (gui_checks.lua) instead of running the checks, paused and
#                  with only the game's own mods besides this one; needs --save. The cursor is parked
#                  at the top edge before each shot, so nothing shows a hover state.
#   --vanilla      with --gallery: without the mod, for the "before" shots
#   --language CODE  run in that game language (e.g. en); the profile is restored afterwards
#   --no-shots     take no screenshots
#   --window WxH   run in a window of that size (e.g. 1280x720) instead of the configured screen mode
#   --font SIZE    text size SMALL, MEDIUM or LARGE
#   --ui-scale F   a fixed UI scale (e.g. 1.5) instead of the automatic one
#                  (window, font and scale: settings.lua is restored afterwards)
# Requires: Steam running, Transport Fever 3 not running, steam_appid.txt in the game folder.
set -euo pipefail

timeout=900
keep_testbench=0
save=""
with_mods=()
only=()
off=()
gallery=0
vanilla=0
mods_first=0
language=""
no_shots=0
window=""
font=""
ui_scale=""
while [ $# -gt 0 ]; do
	case "$1" in
		--timeout) timeout="$2"; shift 2 ;;
		--keep-testbench) keep_testbench=1; shift ;;
		--save) save="$2"; shift 2 ;;
		--with-mod) with_mods+=("$2"); shift 2 ;;
		--mods-first) mods_first=1; shift ;;
		--only) only+=("$2"); shift 2 ;;
		--off) off+=("$2"); shift 2 ;;
		--gallery) gallery=1; shift ;;
		--vanilla) vanilla=1; shift ;;
		--language) language="$2"; shift 2 ;;
		--no-shots) no_shots=1; shift ;;
		--window) window="$2"; shift 2 ;;
		--font) font="$2"; shift 2 ;;
		--ui-scale) ui_scale="$2"; shift 2 ;;
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

if [ "$gallery" -eq 1 ] && [ -z "$save" ]; then echo "--gallery needs --save" >&2; exit 2; fi
if [ "$vanilla" -eq 1 ] && [ "$gallery" -eq 0 ]; then echo "--vanilla needs --gallery" >&2; exit 2; fi

"$repo/tools/deploy.sh" "$mod_dir" "$testbench_dir"

# The game language lives in the profile (language = { code = "de", ... }); a backup is put back
# however this script ends.
profile="$userdata/profile.lua"
profile_backup=""
restore_profile() {
	if [ -n "$profile_backup" ] && [ -f "$profile_backup" ]; then
		cp "$profile_backup" "$profile" && rm -f "$profile_backup"
	fi
}
# --gallery: large text and the full render resolution for sharp, readable crops (settings.lua, also
# put back afterwards)
settings="$userdata/settings.lua"
settings_backup=""
restore_settings() {
	if [ -n "$settings_backup" ] && [ -f "$settings_backup" ]; then
		cp "$settings_backup" "$settings" && rm -f "$settings_backup"
	fi
}
if [ "$gallery" -eq 1 ]; then
	settings_backup="$(mktemp)"
	cp "$settings" "$settings_backup"
	sed -i -E 's/^(\s*)fontScaleClass = "[A-Z]+",/\1fontScaleClass = "LARGE",/; s/^(\s*)resolutionScale = [0-9.]+,/\1resolutionScale = 1,/' \
		"$settings"
fi
# --window, --font, --ui-scale: other screen sizes and text sizes (settings.lua, put back afterwards)
if [ -n "$window$font$ui_scale" ]; then
	if [ -z "$settings_backup" ]; then
		settings_backup="$(mktemp)"
		cp "$settings" "$settings_backup"
	fi
	if [ -n "$window" ]; then
		w="${window%x*}"; h="${window#*x}"
		sed -i -E 's/^(\s*)screenMode = "[A-Z]+",/\1screenMode = "WINDOWED",/; s/^(\s*)windowSize = \{[^}]*\},/\1windowSize = { '"$w"', '"$h"', },/' "$settings"
	fi
	[ -z "$font" ] || sed -i -E 's/^(\s*)fontScaleClass = "[A-Z]+",/\1fontScaleClass = "'"$font"'",/' "$settings"
	[ -z "$ui_scale" ] || sed -i -E 's/^(\s*)uiAutoScaling = (true|false),/\1uiAutoScaling = false,/; s/^(\s*)uiscaling = [0-9.]+,/\1uiscaling = '"$ui_scale"',/' "$settings"
	echo "screen for this run: window=${window:-as configured} font=${font:-as configured} ui scale=${ui_scale:-auto}"
fi
if [ -n "$language" ]; then
	profile_backup="$(mktemp)"
	cp "$profile" "$profile_backup"
	sed -i -E '/language = \{/,/\}/ s/code = "[^"]*"/code = "'"$language"'"/' "$profile"
	grep -q "code = \"$language\"" "$profile" \
		|| { restore_profile; restore_settings; echo "could not set the language" >&2; exit 1; }
	echo "language for this run: $language"
fi
trap 'restore_profile; restore_settings' EXIT

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
if [ -n "$save" ] || [ ${#with_mods[@]} -gt 0 ] || [ ${#only[@]} -gt 0 ] || [ ${#off[@]} -gt 0 ] \
	|| [ "$gallery" -eq 1 ]; then
	extra=""
	for m in "${with_mods[@]}"; do extra="$extra\"$m\", "; done
	only_list=""
	for c in "${only[@]}"; do only_list="$only_list\"$c\", "; done
	off_list=""
	for f in "${off[@]}"; do
		grep -q "^	\"$f\", --" "$mod_dir/content/$mod/gui/settings.lua" \
			|| { echo "unknown feature $f (see settings.FEATURES in gui/settings.lua)" >&2; exit 2; }
		off_list="$off_list\"$f\", "
	done
	staged_fixture="$userdata/staging_area/${mod}_testbench/content/${mod}_testbench/fixture.lua"
	flags=""
	[ "$gallery" -eq 1 ] && flags="$flags gallery = true,"
	[ "$vanilla" -eq 1 ] && flags="$flags vanilla = true,"
	[ "$mods_first" -eq 1 ] && flags="$flags mods_first = true,"
	printf -- '-- Written by spec/ingame/run.sh\nreturn { save = %s, mods = { %s}, only = { %s}, off = { %s},%s }\n' \
		"$fixture_save" "$extra" "$only_list" "$off_list" "$flags" > "$staged_fixture"
	if [ ${#with_mods[@]} -gt 0 ]; then echo "with mods: ${with_mods[*]}"; fi
	if [ ${#off[@]} -gt 0 ]; then echo "features off: ${off[*]}"; fi
fi

launched_at=$(date +%s)
shots_dir="$results_dir/shots-$(date +%Y%m%d-%H%M%S)"
if [ "$gallery" -eq 1 ]; then shots_dir="$results_dir/gallery-$([ "$vanilla" -eq 1 ] && echo vanilla || echo mod)"; fi

# Screenshots for visual review: the testbench logs "[testbench] SHOT <name>" and holds still for a
# few seconds; this saves the game window's content (window_shot.ps1, PrintWindow) to
# $shots_dir/<name>.png. Only the game window is captured, also while other windows lie in front of it.
# The gallery captures the primary screen instead (it moves the cursor over the game, which must be in front).
window_shot_ps1="$(wslpath -w "$repo/spec/ingame/window_shot.ps1")"
capture_screen() {
	if [ "$gallery" -eq 0 ]; then
		powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$window_shot_ps1" -out "$1" \
			< /dev/null > /dev/null 2>&1
		return
	fi
	powershell.exe -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; \$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; \$bmp=New-Object System.Drawing.Bitmap \$b.Width,\$b.Height; [System.Drawing.Graphics]::FromImage(\$bmp).CopyFromScreen(\$b.Left,\$b.Top,0,0,\$bmp.Size); \$bmp.Save('$1')" < /dev/null > /dev/null 2>&1
}
# The cursor at the top edge, half way across (edge scrolling is off in the settings): no hover state.
park_cursor() {
	powershell.exe -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; \$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; [System.Windows.Forms.Cursor]::Position=New-Object System.Drawing.Point ([int](\$b.Left+\$b.Width/2)),\$b.Top" < /dev/null > /dev/null 2>&1
}
# A hover or a click the testbench asks for ("[testbench] MOUSE x y" / "CLICK x y", screen pixels): the
# cursor goes a few pixels off and back, so the game sees it move, and stays there for the next shot.
# The click helper is compiled before the game starts: compiling it while the game runs hung (observed).
mouse_dll_win=""
if [ "$gallery" -eq 1 ]; then
	# on C: (.NET refuses to load an assembly from the WSL share, observed)
	mkdir -p "$results_dir"
	mouse_dll="$results_dir/uio_mouse.dll"
	rm -f "$mouse_dll"
	mouse_dll_win="$(wslpath -w "$mouse_dll")"
	powershell.exe -NoProfile -NonInteractive -Command "Add-Type -OutputAssembly '$mouse_dll_win' -TypeDefinition 'public static class UioMouse { [System.Runtime.InteropServices.DllImport(\"user32.dll\")] public static extern void mouse_event(int f, int dx, int dy, int d, int e); }'" < /dev/null
	[ -f "$mouse_dll" ] || { echo "could not build the mouse helper" >&2; exit 1; }
fi
mouse_at() {
	local click=""
	if [ "${3:-}" = "click" ]; then
		click="[Reflection.Assembly]::LoadFile('$mouse_dll_win') | Out-Null; Start-Sleep -Milliseconds 150; [UioMouse]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 80; [UioMouse]::mouse_event(4,0,0,0,0);"
	fi
	powershell.exe -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; [System.Windows.Forms.Cursor]::Position=New-Object System.Drawing.Point ($1 - 6),($2 - 6); Start-Sleep -Milliseconds 120; [System.Windows.Forms.Cursor]::Position=New-Object System.Drawing.Point $1,$2; $click" < /dev/null >> "$shots_dir/mouse.log" 2>&1
}
watch_shots() {
	set +e # a failed step must not end the watcher
	local done_count=0 steps step hovering=0
	while true; do
		if [ -f "$log" ] && [ "$(stat -c %Y "$log")" -ge "$launched_at" ]; then
			mapfile -t steps < <(grep -aoE "\[testbench\] (SHOT [A-Za-z0-9_.-]+|MOUSE -?[0-9]+ -?[0-9]+|CLICK -?[0-9]+ -?[0-9]+)" "$log" \
				| sed 's/^\[testbench\] //')
			while [ "$done_count" -lt "${#steps[@]}" ]; do
				read -r -a step <<< "${steps[$done_count]}"
				mkdir -p "$shots_dir"
				echo "$(date +%H:%M:%S) ${step[*]}" >> "$shots_dir/mouse.log"
				case "${step[0]}" in
					MOUSE) mouse_at "${step[1]}" "${step[2]}"; hovering=1 ;;
					CLICK) mouse_at "${step[1]}" "${step[2]}" click; hovering=1 ;;
					SHOT)
						if [ "$no_shots" -eq 1 ]; then done_count=$((done_count + 1)); continue; fi
						mkdir -p "$shots_dir"
						# the cursor out of the way, unless the shot shows what it hovers
						if [ "$gallery" -eq 1 ] && [ "$hovering" -eq 0 ]; then park_cursor; sleep 1.5; fi
						capture_screen "$(wslpath -w "$shots_dir")\\${step[1]}.png"
						echo "$(date +%H:%M:%S) captured ${step[1]}" >> "$shots_dir/captures.txt"
						hovering=0
						;;
				esac
				done_count=$((done_count + 1))
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
trap 'kill "$watcher" 2> /dev/null || true; restore_profile; restore_settings' EXIT
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
# (not the testbench's own lines, which may quote such a line)
mod_failures=$(grep -a "\[ui_overhaul\] disabled\|\[ui_overhaul\] .* failed" "$saved" | grep -vc "\[testbench\]" || true)
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
[ "$mod_failures" -eq 0 ] || { echo "mod modules fell back to vanilla ($mod_failures lines):"; grep -a "\[ui_overhaul\] disabled\|\[ui_overhaul\] .* failed" "$saved" | grep -v "\[testbench\]" | cut -c1-300 | head; }
[ "$outcome" = "done" ] && [ "$failed" -eq 0 ] && [ "$passed" -gt 0 ] && [ "$gui_failures" -eq 0 ] && [ "$mod_failures" -eq 0 ]
