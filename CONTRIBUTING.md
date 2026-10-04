# Contributing

Thanks for looking. This file covers the parts of this repository that are hard to find out by trial. Most of them come from one fact: a mistake in a GUI mod can take the whole game UI down with it.

## What you need

- Transport Fever 3 on Windows, for the in-game checks. The offline specs and luacheck run anywhere.
- WSL or another bash with `make`, plus Node.js for the tooling. `make deps` installs the rest (fengari, the luacheck source and the SVG renderer).
- The game's GUI sources for reference. `tools/extract_game_sources.sh` unpacks them to `.game/`. They are not redistributable, so they are not in the repository.

## The gates

```bash
make lint test                     # luacheck, Lua 5.2 syntax rules, offline specs
make test-ingame                   # starts the game, runs the GUI checks on a small new map
make test-ingame SAVE="My Save"    # the same on a temporary copy of a savegame
make test-ingame SAVE="My Save" ONLY="check_a check_b"   # just those GUI checks (to bisect a crash)
make validate                      # the game's mod validator (close the game first)
python3 tools/strings_check.py     # every text the mod uses exists in every language
```

CI runs `make lint test` and the strings check without the game. It cannot run the in-game checks, so a green CI run says nothing about what the game shows. Run `make test-ingame` before you open a pull request, and say in the pull request what you checked in the game and what you did not.

When you pipe a gate's output through `tail` or `grep`, set `set -o pipefail` first. Otherwise a failed lint looks like a pass, and the next in-game run starts a broken build.

## Rules the game enforces

The game's UI is Lua "recipes" in a React-like framework (`gui/main/react.lua`). The engine does not report most mistakes. It drops the entire game UI and leaves a log line in `stdout.txt`.

- **Every recipe returns a layout.** A recipe that returns a `Component`, a `Button` or the bare result of `react.CallOriginalRecipe` fails with "Recipe child must be a layout", and the game has no UI at all. Wrap it in `builtin.BoxLayout{children = {...}}`. `make lint` rejects `return react.CallOriginalRecipe`.
- **The same hooks on every render.** The engine keeps a recipe's hook state by position (`react.useState`, `useRef`, `onStep`, `onMount`, the `engine_react_util.use...` states and a notification type's `useDataState`). Declare them unconditionally and in the same order, before anything that can fail, and keep their callbacks from raising, since a callback such as `useStepStateTimer`'s also runs inside the hook on the first render. No error may escape a recipe either: a recipe of the mod's own declares its hooks, then pcalls the rest and renders an empty layout if it fails. A replacement falls back to the base recipe through a parent that declares fixed hooks and drops a child recipe holding the mod's hooks (`gui/fallback.lua`), so the child unmounts instead of rendering again with fewer hooks, and the choice holds for the session instead of changing from render to render. A Lua copy of a base recipe may fail where the base would; what the copy adds is protected like the mod's own code.
- **Lua 5.2.** The game embeds Lua 5.2, so `\u{...}` escapes, `//`, bitwise operators and the `utf8` library break module loading. Write non-ASCII characters as `\x` byte escapes. luacheck runs with `std = "lua52"`, and `make lint` greps for the rest.
- **No GUI-thread calls in timer callbacks.** `api.util.getApplicationTime()` inside a `useStepStateTimer` or `onStepTimer` callback crashes the game natively, without a Lua error. `_()` in a timer callback is also unsafe. Read engine data there and format it during rendering.
- **Fully qualified paths after load time.** `require("/x.lua")` resolves inside this mod only while a module is being loaded. A `require` at render time or in a callback resolves to the base game, so write `"ui_overhaul_1::/ui_overhaul/..."`.
- **Texts come from `strings.json`.** Use plain `_()`. `nGetText` does not see a mod's `strings.json`.

## How a change is built

Each change is one module in `src/ui_overhaul/content/ui_overhaul/gui/`, plus two small files the engine loads:

- `<name>.res.lua` registers it, as a `react-plugin ::<ExtensionPoint>` or a `react-replacement-config`.
- `<name>.script.lua` is the stub the resource points at. It loads the module through `guard.lua` with `pcall` and installs it. If loading or installing fails, the stub logs one `[ui_overhaul]` line and the game keeps its vanilla screen.

Keep this split for new modules. A replacement recipe should call the original recipe whenever it can (`react.CallOriginalRecipe`) and change only what it has to, so that game updates break as little as possible. Logic that does not need the engine goes in `core/`, with specs in `spec/` against the mock engine.

`docs/api_cookbook.md` lists the engine APIs this mod uses and how they behave. Check what an API does in the game before you write code that depends on it, and add what you find to the cookbook.

## Other mods

Only one mod can replace a given recipe; the one that registers last wins. The README lists the recipes this mod replaces. Before you replace another one, see whether an extension point (`react-plugin`) or a wrapper around a module function can do the job, and add the recipe to the README's list if not.

## Checking what the player sees

A change is not finished until you have looked at it in the game. `make test-ingame` writes a screenshot of every changed screen to `spec/ingame/results/` (the checks in `spec/ingame/ui_overhaul_testbench/` call `shot`). Compare them with the vanilla screen: sizes, spacing, fonts, nothing clipped or cut off. Use the game's widgets and style classes instead of your own colours and sizes.

The screenshot covers the primary screen. Keep the game in front while the checks run, and delete the screenshots once you are done with them, since they can show whatever else is on that screen.

Hovers, second clicks and anything that needs a long game session can't be automated. List them under "Still unverified" in the pull request.

## Scope

The mod improves the screens the game already has. A change should feel as if the game always worked that way, with nothing new for the player to learn.

- No new windows, unless the goal cannot be reached inside an existing one. Open an issue first.
- No new notifications, and no change to which game notifications are hidden.
- Gameplay screens only: saving, loading and the main menu are out of scope.

## Texts

Every text the player sees goes in `src/ui_overhaul/strings.json`, in all the game's languages (`en`, `de`, `fr`, `it`, `es`, `nl`, `ja`, `ko`, `pl`, `pt_BR`, `ru`, `zh_CN`, `zh_TW`, the game's own language folders). Reuse the game's own terms for the same thing (its catalogs are in `base/strings/<lang>/LC_MESSAGES/base.mo`). `tools/strings_check.py` reports missing translations and keys the code no longer uses. Write the way the game does: short, plain words, sentence case.

## Pull requests and commits

Say which screen behaves differently and what stays the same. Keep behaviour changes and restructuring in separate commits.

A commit message is a short summary line, then a few lines on what changed and why.
