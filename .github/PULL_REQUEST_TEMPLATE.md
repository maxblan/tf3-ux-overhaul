<!-- markdownlint-disable-file MD041 -->
<!-- A pull request template has no title of its own: its first heading is a section of the pull
     request body, not a document title. -->

## What changes

<!-- Which vanilla screen behaves differently afterwards, and what stays as it was. -->

## Why

<!-- The problem a player has today: the clicks, the missing number, the window that closes. -->

## How it was verified

<!-- Delete what does not apply, and say what each check showed. -->

- [ ] `make lint test`
- [ ] `make test-ingame` (new map) or `make test-ingame SAVE="..."` (copy of a savegame)
- [ ] Compared the screenshots in `spec/ingame/results/` with the vanilla screen: sizes, spacing, fonts, nothing clipped
- [ ] `make validate` (the game's mod validator)
- [ ] Checked `stdout.txt` for `[ui_overhaul]` lines and Lua errors

**Still unverified:**

<!-- What only a click, a hover or a long game session would show. -->

## Checklist

- [ ] The change sits in an existing screen and looks like vanilla; nothing new to learn
- [ ] Every recipe returns a layout, and a failure falls back to the vanilla screen
- [ ] Timer callbacks only read the engine (no `api.util.getApplicationTime`, no `_()`)
- [ ] Lua 5.2 only (no `\u{}`, `//` or bitwise operators)
- [ ] New texts are in `strings.json` in English and German
- [ ] No new notifications, and no change to which game notifications are hidden
