# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

UI Overhaul is a GUI-only Transport Fever 3 mod (mod id `ui_overhaul_1`) that improves the game's own screens in place. The game embeds Lua 5.2; the GUI is Lua "recipes" in a React-like framework (`::/gui/main/react.lua`). Read `CONTRIBUTING.md` before changing code: it holds the rules the game enforces, and breaking them drops the whole game UI. `docs/design.md` maps every change to its module and hook, and explains the installer and load-order machinery in depth.

## Commands

The environment is WSL with the game on Windows. Node is the Windows `node.exe`; there is no native Lua, so specs and lint run on fengari (`tools/lua/`) unless `busted`/`luacheck` are installed.

```bash
make deps                                  # once: fengari, luacheck source, Lua Language Server, SVG renderer
make lint typecheck test                   # the offline gates (CI runs these)
node.exe tools/lua/run_specs.js minimize_spec   # one spec file (substring filter on the path; use a file-name fragment, node.exe sees backslashes)
python3 tools/strings_check.py             # translations (CI uses --no-game)
make content                               # regenerate _content.json after adding/removing files (CI checks it)
make test-ingame                           # launches the game, runs the GUI checks, screenshots to spec/ingame/results/
make test-ingame SAVE="My Save" ONLY="check_a" WITH="mod_a" MODS_FIRST=1 OFF="terminals" WINDOW=1280x720 FONT=LARGE UI_SCALE=1.5 NO_SHOTS=1
make validate                              # the game's validator (game must be closed)
```

Set `set -o pipefail` before piping a gate through `tail`/`grep`, or a failure looks like a pass. CI cannot run the game: a green CI says nothing about what the game shows. The game log is `crash_dump/stdout.txt` under the Steam userdata folder; the mod's lines start with `[ui_overhaul]`.

`make lint` also greps `src/` for Lua 5.3 syntax (`//`, bitwise ops, `\u{}`), `return react.CallOriginalRecipe` and `raw(get|set|equal|len)` (absent in the game's GUI Lua state). `make typecheck` is strict: every diagnostic is an error, functions need `---@param`/`---@return`, the mod's types are named `uo.<...>`, and engine/base-game APIs used must be stubbed in `types/` from the game's Teal declarations.

## Architecture

- `src/ui_overhaul/content/ui_overhaul/core/`: pure Lua, no engine access, specs in `spec/core/`.
- `src/ui_overhaul/content/ui_overhaul/gui/`: one module per change, each with `install(replacement_api)`. Specs in `spec/gui/` run against `spec/support/mock_engine.lua` and `fake_react.lua`; `spec/support/setup.lua` mirrors the game's `require` resolution.
- `spec/ingame/ui_overhaul_testbench/`: a second mod deployed alongside; `gui_checks.lua` holds the named checks (`ONLY=`), driven by `spec/ingame/run.sh`.
- `.game/` (gitignored, from `tools/extract_game_sources.sh`): the game's GUI sources, the reference for any base recipe you touch.

Install flow, which spans `installer.lua`, `settings.lua`, `priority.lua`, `guard.lua` and `fallback.lua`:

1. `installer_early.res.lua` (order -1e9) and `installer_late.res.lua` (order 1e9) both use the stub `installer.script.lua`, which loads `installer.lua` through `guard.lua` in `pcall`.
2. Early: `settings.lua` reads the player's switches (`mod.json` params); features switched off are never installed. Each module in `INSTALLS` runs in `pcall`; its function wraps go in via `priority.chain`, and its `ReplaceRecipe` calls are only recorded.
3. Between the two configs, `priority.lua` logs every write to loaded modules' function fields and to the recipe registry, with the mod that made it (from `debug.getinfo`).
4. Late (`priority.late`): the mod that comes **first in the mod list** wins a feature where both replace the same recipe; shared function wraps keep both. `priority.OVERLAPS` lists mods that show the same thing in their own way, so one of the two is held back. Chains are then settled once, so no call checks settings at runtime.
5. Stylesheets (`*.css.lua`, `styles.lua`) run before settings and load order are known, so every rule must select only `uio-` classes / `R::Uio` recipes, or `Window!uio-on-<feature> ` for the game's own elements (`spec/gui/stylesheets_spec.lua` checks this).

Adding a feature touches `installer.lua` (`INSTALLS`), `settings.lua` (`FEATURES`), and `mod.json` `params` in the same order (`settings_spec.lua` checks it), plus the param's texts in `strings.json` for all 13 game languages. A plugin also needs `<name>.res.lua` (`react-plugin ::<ExtensionPoint>`) and a `<name>.script.lua` stub that calls `guard.plugin`. Then run `make content`.

## Rules worth repeating

- A recipe must return a layout; wrap `react.CallOriginalRecipe(...)` in `builtin.BoxLayout`. A wrapper recipe (`react.RegisterWrapperRecipe`) is the exception: it returns its wrapped recipe's node (in pcall; `{}` for none, never nil).
- Hooks are declared unconditionally and in the same order on every render, before anything that can fail; no error may escape a recipe (pcall after the hooks, render an empty layout on failure).
- Wrap module functions with `priority.chain(module, "field", ...)`, never by assigning; `builtin.*` widgets with `builtin_wraps.wrap`. Exception: a recipe field other mods wrap with `RegisterWrapperRecipe` gets a wrapper recipe assigned directly (the field must stay a recipe), see `window_tweaks.wrap_bar` / `settle_sell`.
- `require("/x.lua")` resolves inside this mod only at load time; at render time or in callbacks use `"ui_overhaul_1::/ui_overhaul/..."`.
- No GUI-thread calls (`api.util.getApplicationTime()`, `_()`) inside timer callbacks: native crash.
- Texts via plain `_()` from `src/ui_overhaul/strings.json`, reusing the game's own terms.
- Prefer calling the original recipe and changing only what is needed. Record verified engine behaviour in `docs/api_cookbook.md`, and add a replaced recipe to the README's list.
- Keep `src/ui_overhaul/_metadata/mod.io_fileid.txt`: it links publishes to the existing mod.io entry.
- Scope: only information the game already shows somewhere (it may move to where it's needed; what the game computes but never shows stays out), no new windows, no new notifications, gameplay screens only. New controls are fine unless they can fire by accident.
- Call a replaced base recipe through `guard.base(name, recipe)`, made at load time, never `react.CallOriginalRecipe(module.Field, ...)` at render time. `make content` regenerates `gui/needs.lua` (base fields per module, checked at load by `compat.lua`); CI fails if it is stale.
- Keep unrelated changes on separate switches (`window_tweaks.lua` has one `install_*` per feature).
- Never `ReplaceRecipe` a recipe other mods wrap with `react.RegisterWrapperRecipe` (e.g. `entity_window_util.ActionButtonBar`): a wrapper must return exactly its wrapped recipe's node, else "Wrapper recipe must return child" freezes the window. Wrap it too (`window_tweaks.wrap_bar`).
