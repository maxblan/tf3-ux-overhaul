# UI Overhaul

A Transport Fever 3 mod that makes the game's own screens faster to read and quicker to act in. It adds no new windows or notifications: the vanilla Line Manager, Statistics, entity windows and construction menu simply show more and need fewer clicks, so there is nothing new to learn.

## What changes

**Line Manager**
- Every line row shows its vehicle count and 12-month balance (red when losing money); every vehicle row shows its age (red once the lifespan is reached).
- Reopening it selects the line you had selected before.
- Cloning several vehicles at once, or replacing several, asks first, using the Line Manager's own prompt. With two or more lines ticked, clicking a station creates a new line without moving all their vehicles onto it.

**Line window**
- The Vehicles card has *Add Vehicle* (a copy of the line's newest vehicle) and *Remove Vehicle* (sends the oldest to a depot and sells it there).
- A *Stops* card lists every stop with its waiting passengers (cargo in the tooltip).

**Statistics**
- Lines: quick filters *All / Losing money / Problems / No vehicles*, and the totals of the rows shown (lines, vehicles, balance). Vehicles sort by count, Balance sorts by the value it shows.

**Windows**
- Statistics, Line Manager, Finances, Company and the notification log can be open side by side and next to entity windows. Clicking the map no longer closes them, and *Manage Line* no longer closes the line window.
- Sections you opened in entity windows stay open the next time, and several can be open at once.
- *Sell* in the vehicle window asks once more before selling.

**Town and company**
- The town window names what limits growth ("Limited by Traffic") and shows the progress to the next level as text.
- A perk that is locked although the game bar already shows the required rank says *Promotion pending - open the Company window*.

**Construction**
- The Rail and Tracks menus show each other's tabs, as do Road and Roads; each button still opens on its own first tab.
- Tracks are listed fastest first (available ones before future ones), so the default track is the best you can build.
- *Configure* on a station opens Tracks, Platforms, Road Access or Building first instead of Decoration.
- The bulldozer's tooltip warns before removing a station that lines stop at.

**Game bar and store**
- The Earnings tooltip also shows the cash flow of the last 30 days and the 30 days before.
- The vehicle store lists the newest models first (and preselects the newest) and keeps your sort for the session.

## Compatibility

- Safe to add to and remove from savegames: the mod changes only the user interface and adds no game script.
- Built on the game's official UI extension points and recipe replacement. Every change falls back to the vanilla screen if it fails, so an error never takes the game's UI down.
- Other mods that replace the same vanilla UI parts (the Line Manager's vehicle list, the Statistics lines tab, the line window's vehicle card, the earnings display, the tool stack, the action bar) conflict with it; tested together with *Timetables* and *Auto Line Namer*.
- English and German.

## Development

This repository follows [tf3-mod-template](https://github.com/maxblan/tf3-mod-template): `make lint test` (offline), `make test-ingame` (in-game checks on a small new map) or `make test-ingame SAVE="<savegame>"` (on a temporary copy of a savegame), which also takes screenshots of each UI state into `spec/ingame/results/`.

- `docs/inventory/`: code-level inventory of the game's UI, the basis of the mod.
- `docs/PLAN.md`, `docs/flows_audit_v2.md`: plan and the ranked list of further improvements.
- `docs/api_cookbook.md`: engine API reference for GUI work.
- `tools/extract_game_sources.sh`: extracts the game's GUI sources to `.game/` for reference.
- `src/ui_overhaul/content/ui_overhaul/gui/`: one module per change, each installed through a guarded stub (`*.script.lua`, `guard.lua`).

## License

[MIT](LICENSE). Transport Fever 3 is a trademark of Urban Games; this project is not affiliated with Urban Games or Paradox Interactive.
