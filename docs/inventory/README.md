# TF3 UI/UX inventory

An inventory of Transport Fever 3's in-game UI, read from the game's GUI source (build 40408). Every claim cites `file:line`. Paths that start with `SCR/game/...` correspond to `.game/game/...` after you run `tools/extract_game_sources.sh`.

| File | Area | Contents |
|---|---|---|
| [00_moddability.md](00_moddability.md) | How a mod can change the GUI | 18 extension points, recipe replacement, windows, events, data APIs, commands, risks, test approach |
| [01_shell_hud.md](01_shell_hud.md) | In-game shell | game bar, HUD, window manager (tool stack), keybindings, speed/date/money, how windows are opened |
| [01b_notifications.md](01b_notifications.md) | Notifications | 27 notification types, popups, log, HUD warning icons, problems that are hidden by default |
| [01c_layers_maphud.md](01c_layers_maphud.md) | Map layers and HUD | 11 layers, map icons, tooltips |
| [02_construction.md](02_construction.md) | Construction | 17 menus, sublists, tool options, modules, search, bulldozer |
| [03_lines_vehicles.md](03_lines_vehicles.md) | Lines and vehicles | Line/Vehicle Manager, vehicle store, stops, cargo filter, rename and dispatch schemes |
| [04_entity_windows.md](04_entity_windows.md) | Entity windows | vehicle, line, station, town, industry, depot and other windows; stacking and pinning |
| [05_statistics_menus.md](05_statistics_menus.md) | Overview | statistics (7 tabs), finances, pause/save/load, settings, map editor |
| [keybindings.txt](keybindings.txt) | Keys | the bound input actions, read from the player's `settings_keys_v3.lua` |

Each area file has the same four sections: 1. Surfaces, 2. Task flows (with click counts), 3. Friction findings (rated High/Med/Low) and 4. Improvement opportunities (with the saving and how it could be modded).

## Ten facts that shape GUI modding

1. The whole in-game GUI is Lua/Teal React-style "recipes" (`gui/main/react.lua`), about 117k lines. The engine draws only the built-in widgets.
2. Mods hook in with resource files instead of shadowing base files:
   - `react-plugin` adds content to one of 18 extension points;
   - `react-replacement-config` replaces one exported recipe before the UI starts; the last mod to register wins;
   - data resources (`menu_category`, `construction_tool`, `notification`, `rename_scheme`, ...) add or change content.
3. The player sees almost no status without clicking:
   - the game bar shows only money, "earnings" (year to date, though the label doesn't say so) and lifetime passengers and cargo;
   - the notification button has no badge.
4. Problem notifications are switched off by default in free play:
   - line, station and vehicle problems, overcrowding and stuck vehicles are all created already ignored;
   - unprofitable lines, low cash, old vehicles and lines without vehicles have no notification type at all.
5. Only one tool window can be open at a time. Statistics, the Line Manager, Finances and Construction close each other. An entity window opened from a list hides that list, and on PC a click on the map closes everything that isn't pinned.
6. The Line/Vehicle Manager is about 8,500 lines with no extension point:
   - the line list has one column, can't be sorted and shows no balance, utilization or vehicle count;
   - the vehicle list shows no age or condition;
   - clicking a line selects all its vehicles, so Clone copies the whole fleet without asking.
7. Statistics has seven sortable tabs, but:
   - there are no totals and no bulk actions;
   - it shows no trend;
   - problems are spread over six tabs;
   - stations without lines are hidden.
8. Entity windows show little status:
   - the line window has no stop list, no waiting counts and no "add vehicle" button;
   - station waiting counts cover passengers only;
   - the industry supply chain sits behind a collapsed section;
   - town ratings show as colours only.
   The station and town-building extension points are empty, so a mod can fill them.
9. Construction:
   - rail work is split across the Rail and Tracks menus, and roads across Road and Roads;
   - the default track is the slowest one;
   - search only covers the current menu;
   - there are no favourites and no undo.
10. Mods can't add new hotkeys. The input actions are hard-coded in the engine, so a mod can only open its UI from buttons, radial-menu entries or existing input actions.
