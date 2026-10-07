# Contributing

Thanks for looking. This file covers the parts of this repository that are hard to find out by trial. Most of them come from one fact: a mistake in a GUI mod can take the whole game UI down with it.

## What you need

- Transport Fever 3 on Windows, for the in-game checks. The offline specs and luacheck run anywhere.
- WSL or another bash with `make`, plus Node.js for the tooling. `make deps` installs the rest (fengari, the luacheck source and the SVG renderer).
- The game's GUI sources for reference. `tools/extract_game_sources.sh` unpacks them to `.game/`. They are not redistributable, so they are not in the repository.

## The gates

```bash
make lint typecheck test           # luacheck, Lua 5.2 syntax rules, strict type check, offline specs
make test-ingame                   # starts the game, runs the GUI checks on a small new map
make test-ingame SAVE="My Save"    # the same on a temporary copy of a savegame
make test-ingame SAVE="My Save" ONLY="check_a check_b"   # just those GUI checks (to bisect a crash)
make test-ingame SAVE="My Save" WINDOW=1280x720 FONT=LARGE  # another screen and text size (UI_SCALE=1.5 too)
make validate                      # the game's mod validator (close the game first)
python3 tools/strings_check.py     # every text the mod uses exists in every language
```

CI runs `make lint typecheck test` and the strings check without the game. It cannot run the in-game checks, so a green CI run says nothing about what the game shows. Run `make test-ingame` before you open a pull request, and say in the pull request what you checked in the game and what you did not.

When you pipe a gate's output through `tail` or `grep`, set `set -o pipefail` first. Otherwise a failed lint looks like a pass, and the next in-game run starts a broken build.

## Types

`make typecheck` runs the Lua Language Server with `.luarc.json`, where every diagnostic group is an error, including values whose type it cannot infer. It must report nothing, and editors with the Lua extension show the same errors.

- Give every function `---@param` and `---@return` annotations, and declare data shapes as `---@class`. The mod's own types are named `uo.<...>`.
- The engine API (`api`, `app`) and the base-game modules the mod requires (`::/gui/main/react.lua` and so on) have stubs in `types/`. They are typed from the game's Teal declarations (`.game/game/apidef/` after `tools/extract_game_sources.sh`) and declare only what the mod uses. When you use something new, add it there with the game's types.
- `tools/luals/plugin.lua` resolves the game's require paths for the language server. The `different-requires` check is off because a module is required by its short path at load time and by its fully qualified path afterwards (see below).
- No unexplained `any`, `---@cast` or suppression. A suppression is `---@diagnostic disable-next-line: <code>` with the reason next to it.

## Rules the game enforces

The game's UI is Lua "recipes" in a React-like framework (`gui/main/react.lua`). The engine does not report most mistakes. It drops the entire game UI and leaves a log line in `stdout.txt`.

- **Every recipe returns a layout.** A recipe that returns a `Component`, a `Button` or the bare result of `react.CallOriginalRecipe` fails with "Recipe child must be a layout", and the game has no UI at all. Wrap it in `builtin.BoxLayout{children = {...}}`. `make lint` rejects `return react.CallOriginalRecipe`.
- **The same hooks on every render.** The engine keeps a recipe's hook state by position (`react.useState`, `useRef`, `onStep`, `onMount`, the `engine_react_util.use...` states and a notification type's `useDataState`). Declare them unconditionally and in the same order, before anything that can fail, and keep their callbacks from raising, since a callback such as `useStepStateTimer`'s also runs inside the hook on the first render. No error may escape a recipe either: a recipe of the mod's own declares its hooks, then pcalls the rest and renders an empty layout if it fails. A replacement falls back to the base recipe through a parent that declares fixed hooks and drops a child recipe holding the mod's hooks (`gui/fallback.lua`), so the child unmounts instead of rendering again with fewer hooks, and the choice holds for the session instead of changing from render to render. A Lua copy of a base recipe may fail where the base would; what the copy adds is protected like the mod's own code.
- **Lua 5.2.** The game embeds Lua 5.2, so `\u{...}` escapes, `//`, bitwise operators and the `utf8` library break module loading. Write non-ASCII characters as `\x` byte escapes. luacheck runs with `std = "lua52"`, and `make lint` greps for the rest.
- **No GUI-thread calls in timer callbacks.** `api.util.getApplicationTime()` inside a `useStepStateTimer` or `onStepTimer` callback crashes the game natively, without a Lua error. `_()` in a timer callback is also unsafe. Read engine data there and format it during rendering.
- **Fully qualified paths after load time.** `require("/x.lua")` resolves inside this mod only while a module is being loaded. A `require` at render time or in a callback resolves to the base game, so write `"ui_overhaul_1::/ui_overhaul/..."`.
- **Texts come from `strings.json`.** Use plain `_()`. `nGetText` does not see a mod's `strings.json`.

## How a change is built

Each change is one module in `src/ui_overhaul/content/ui_overhaul/gui/` with an `install(replacement_api)` function, and one entry in each of three lists:

- `installer.lua` (`INSTALLS`): the module, the feature it belongs to and a label for the log. The installer runs it before every other mod's replacement config, in `pcall`; if it fails, one `[ui_overhaul]` line is logged and the game keeps its vanilla screen.
- `settings.lua` (`FEATURES`) and the `params` in `mod.json`, in the same order (`spec/gui/settings_spec.lua` checks it), with the param's name and tooltip in `strings.json` in every language. A feature is one switch for the player; several modules can share one, and one module can serve several (an `fn` per feature, as `window_tweaks.lua` has). Keep unrelated changes on separate switches, so a player who wants one of them off keeps the others.
- A plugin also needs `<name>.res.lua` (`react-plugin ::<ExtensionPoint>`) and a stub in `<name>.script.lua` that registers its recipe through `guard.plugin(path, field, feature)`.

Inside `install`:

- Replace a recipe with `replacement_api.ReplaceRecipe` as usual: the installer hands in a stand-in that `priority.lua` applies later, unless a mod that comes first in the mod list replaced the same recipe.
- Wrap a module function with `priority.chain(module, "field", function(previous) return wrapper end)`, never by assigning the field. A recipe that other mods wrap with `react.RegisterWrapperRecipe` must not be replaced: their wrapper has to return a node of exactly that recipe, and with a replacement it gets the replacement's ("Wrapper recipe must return child", the window freezes). Wrap it the same way instead (`window_tweaks.wrap_bar`); the field must then hold a recipe at all times, so it is set directly, not through `priority.chain`. Pass `true` as the fourth argument for a function many mods wrap for their own reasons (widgets, `react.fireEvent`, `react.useState`). Wrap a `builtin.*` widget with `builtin_wraps.wrap`.
- Where another mod shows the same thing in its own way without sharing a recipe or a function, and changes nothing else, add it to `priority.OVERLAPS`: where UI Overhaul comes first, all its GUI changes are held back.
- A stylesheet rule must select something only this mod puts there: a `uio-` class or an `R::Uio` recipe. The game runs stylesheets before it knows the settings, so a rule on the game's own elements in a window starts with `Window!uio-on-<feature> ` (add the feature to `styles.FEATURES`); `make test` checks every rule.

A replacement recipe should call the original recipe whenever it can and change only what it has to, so that game updates break as little as possible. Call it through `guard.base(name, recipe)`, made while the module loads with the recipe the base module holds then: it calls `react.CallOriginalRecipe` in `pcall` and gives an empty layout where the original makes no node or raises (for example because another mod has since put a plain function in that field, which the framework does not know as a recipe). Never pass the module field read at render time.

`make content` also regenerates `gui/needs.lua` (`tools/needs.py`): every field each module reads from a base module. Before a feature installs, `gui/compat.lua` checks the game still has all of them, also those of the modules it requires and of its plugins; a feature that misses one stays vanilla and the log names what is missing. CI fails if the file is out of date. Logic that does not need the engine goes in `core/`, with specs in `spec/` against the mock engine.

`docs/api_cookbook.md` lists the engine APIs this mod uses and how they behave. Check what an API does in the game before you write code that depends on it, and add what you find to the cookbook.

## Other mods

Where this mod and another change the same part, the one that comes first in the mod list wins (`priority.lua`, docs/design.md). Before you replace a recipe, see whether an extension point (`react-plugin`) or a wrapper around a module function can do the job, and add the recipe to the README's list if not. Check a change with the mods it touches, in both orders: `make test-ingame SAVE="..." WITH="mod_a mod_b"` and again with `MODS_FIRST=1`. The log lines `[ui_overhaul] feature ...` at the start of a run show what was decided.

## Checking what the player sees

A change is not finished until you have looked at it in the game. `make test-ingame` writes a screenshot of every changed screen to `spec/ingame/results/` (the checks in `spec/ingame/ui_overhaul_testbench/` call `shot`). Compare them with the vanilla screen: sizes, spacing, fonts, nothing clipped or cut off. Use the game's widgets and style classes instead of your own colours and sizes.

The screenshot shows only the game window (`spec/ingame/window_shot.ps1`), also while other windows lie in front of it, so you can use the computer during a run. Only the gallery (`--gallery`) captures the primary screen and needs the game in front. A check can also ask for a real mouse click (`[testbench] CLICK x y`, done by `spec/ingame/mouse.ps1`, e.g. the title row's rename button): it brings the game to the front and skips the click, logged in the shots' `mouse.log`, where another window still lies over the game, so leave mouse and keyboard alone while such checks run.

Check other screen shapes and text sizes too (`WINDOW=1024x768`, `WINDOW=2560x1080`, `FONT=LARGE`, `UI_SCALE=1.5`): positions in the game's GUI are parts of the screen, and a window the game opens near an edge can grow past it once its content is laid out (docs/api_cookbook.md, 9.3).

Most hovers, second clicks and anything that needs a long game session aren't automated. List them under "Still unverified" in the pull request. To find which mod of a savegame causes a crash, leave mods out one by one: `WITHOUT="mod_a mod_b"` (also `ui_overhaul_1`, to see whether the game crashes on its own).

## Scope

The mod improves the screens the game already has. A change should feel as if the game always worked that way, with nothing new for the player to learn.

- Only information the game already shows somewhere. A figure may appear on another screen where it is needed (a vehicle's load in the Line Manager, because the vehicle window shows it), but a figure the game computes and never shows (an industry's chance to expand, speeds on slopes, a balance sheet) is out, however useful. Before you build something, name the vanilla screen that already shows it.
- New controls are fine where they cannot fire by accident: no input the player uses for something else (the mouse wheel over a list that scrolls) may change a value.
- No new windows, unless the goal cannot be reached inside an existing one. Open an issue first.
- No new notifications, and no change to which game notifications are hidden.
- Gameplay screens only: saving, loading and the main menu are out of scope.

## Texts

Every text the player sees goes in `src/ui_overhaul/strings.json`, in all the game's languages (`en`, `de`, `fr`, `it`, `es`, `nl`, `ja`, `ko`, `pl`, `pt_BR`, `ru`, `zh_CN`, `zh_TW`, the game's own language folders). Reuse the game's own terms for the same thing (its catalogs are in `base/strings/<lang>/LC_MESSAGES/base.mo`). `tools/strings_check.py` reports missing translations and keys the code no longer uses. Write the way the game does: short, plain words, sentence case.

## Pull requests and commits

Say which screen behaves differently and what stays the same. Keep behaviour changes and restructuring in separate commits.

A commit message is a short summary line, then a few lines on what changed and why.
