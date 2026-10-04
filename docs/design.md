# UI Overhaul design

UI Overhaul changes the game's own screens so that players read the state of their network faster and act on it with fewer clicks. It works inside the vanilla Line Manager, Statistics, entity windows, construction menu, notification ridge and game bar. The code-level inventory of those screens is in [inventory/](inventory/README.md), and the ranked list of further changes is in [improvements.md](improvements.md).

## Design rules

1. Improve the game's own screens in place. A change should feel as if the game always worked that way.
2. Keep the vanilla look. Use the game's widgets and style classes. Replacement recipes are registered under the base recipe names, so the base stylesheet applies to them unchanged.
3. Nothing new for players to learn. The mod fills in figures, fixes sorting and removes clicks in places players already look.
4. New UI only when the goal cannot be reached inside an existing screen, and then in vanilla style. The Stops card in the line window and the model row above the Line Manager's vehicle list are of this kind.
5. No new notifications, and no change to which notifications the game shows or hides. The notification ridge groups icons of the same kind; which notifications exist is left to the game.
6. Gameplay screens only. Saving, loading, the pause menu and the main menu stay vanilla.
7. Actions that touch many vehicles at once ask first, in the game's own question prompt (clone, replace or modify several vehicles) or with a second click (Sell in the vehicle window). Single actions stay instant.

## What the mod changes

The player-facing list is in the [README](../README.md#what-changes). This table maps each change to its module in `src/ui_overhaul/content/ui_overhaul/gui/` and to the hook it uses.

| Screen | Change | Module | Hook |
|---|---|---|---|
| Line Manager | cargo icons, vehicle count and 12-month balance in line rows; age in vehicle rows | `lvm_rows.lua` | replaces `line_react_util.ManagerNotificationWidget`, calls the original |
| Line Manager | model row above the vehicle list, *In all lines*, Shift+click selects a model | `lvm_models.lua`, `lvm_tweaks.lua` | replaces `vehicle_list_react_util.VehicleList`; wraps the manager's `selectVehicles` |
| Line Manager | station click with several lines selected does not move their vehicles | `lvm_tweaks.lua` | wraps `commonParams.newLine` |
| Line Manager | confirmation before cloning, replacing or modifying more than one vehicle; reopening selects the last line | `lvm_tweaks.lua` | patches `react.fireEvent` (`duplicateVehicles`) and `vehicle_react_util.HandleVehicleChanges`; uses the tool stack's pop hook |
| Line Manager | *Select Terminals* with three buttons per terminal | `terminals.lua` | wraps the module function `popover_react_util.PopoverWindowContent`; swaps only a popover with the Line Manager's parameters |
| Station window | *Select Terminals* button for each line stop in the Terminals list | `station_terminals.lua`, `terminals.lua` | wraps the global `orderedPairs` and `gui_react_util.makeHorizontalSpacer` while the file-local recipe `TerminalStops` renders; off while another mod replaces the station window |
| Line window | *Add Vehicle* and *Remove Vehicle* in the Vehicles card | `line_vehicles.lua` | replaces `line_eow.LineVehiclesPlugin` |
| Line window | Stops card, with a *Select Terminals* button per stop; unreachable stops greyed with the base problem text | `cards.lua`, `terminals.lua`, `core/line_problems.lua` | `react-plugin ::LineEowExtensionPoint`, `order = 55` |
| Line Manager | *Select Terminals*: preferred terminal highlighted, unusable or unreachable terminals greyed with the reason | `terminals.lua`, `core/line_problems.lua` | as *Select Terminals* above |
| Line Manager | add-stop hover names a missing path from the stop before or to the next | `lvm_tweaks.lua` | replaces `manager_tooltips_util.LMAddStop`; `api.engine.util.pathfinding.findPathNodeToNode` |
| Statistics | Lines, Vehicles and Stations tabs: quick filters, totals, sorting fixes | `statistics_lines.lua`, `statistics_vehicles.lua`, `statistics_stations.lua`, `statistics_common.lua` | Lua conversions of the base tabs, replacing them |
| Statistics | Warehouses tab: cargo icons with quantities, cargo picker that filters and sorts, quick filters, totals | `statistics_warehouses.lua` | Lua conversion of the base tab, replacing it |
| Windows | tool windows side by side, kept open on map clicks | `tool_stack.lua` | replaces `builtin.ToolStack` |
| Entity windows | minimize to the title bar | `minimize.lua` | wraps `make_entity_window.makeEntityWindowContent`: the content recipe renders inside `UioMinimizable` (not `builtin.Window`: window wrapper recipes registered later would no longer find the builtin, and the game crashes) |
| Entity windows | sections stay open; *Sell* needs a second click | `window_tweaks.lua` | patches `content_card.makeContentCardsCollapsibleFunctions`; replaces `entity_window_util.ActionButtonBar` |
| Map | vehicle hover tooltip: line, next stop, speed, load, condition, delivery quality | `vehicle_tooltip.lua`, `vehicle_info.lua` | replaces `game_tooltips.DefaultEntityToolTip`, calls the original |
| Line Manager, line window | load and condition in vehicle rows, the five figures in the tooltip | `lvm_rows.lua`, `line_vehicles.lua`, `vehicle_info.lua` | as the rows and Vehicles card above |
| Vehicle window | Performance card (rating, slope speeds loaded and empty); slope speeds in the store cart's Performance tooltip | `performance.lua` | `react-plugin ::VehicleEowExtensionPoint`, `order = 55`; wraps `vehicle_util.getPowerRatingTextAndToolTip` and `builtin.TextView` while `VehicleCart` renders |
| Industry window | Development card (recipes, level, expansion chance, blockers), Served by card (lines) | `industry_cards.lua`, `core/industry_development.lua` | `react-plugin ::IndustryEowExtensionPoint`, `order = 15` |
| Town window | growth bottleneck and progress to the next level as text | `window_tweaks.lua` | patches `content_card.makeRecipeAndParam` while `TownLevelPlugin` renders |
| Construction | locked perk says *Promotion pending* | `window_tweaks.lua` | patches `company_util.getConstructionDisableReason` (GUI state only) |
| Construction | merged Rail/Tracks and Road/Roads menus, fastest track first, module tab order, bulldozer warning | `construction.lua` | patches `construction_react_util.getMenuCategories` and `getActionParams` |
| Construction | settings panel and Settings window stay above the game bar at large scales | `construction.css.lua` | CSS: height limits in `vh`, bottom padding per text scale |
| Construction | gradient, curve radius, elevation, bridge height and tunnel depth in the build tooltip | `construction.lua`, `core/geometry.lua` | `getActionParams`: wraps `getProposalStringsFn` of the track and street builders |
| Sliders | mouse wheel, snap points with ticks, typed values | `sliders.lua`, `core/slider_snap.lua` | wraps the module fields `builtin.Slider` (recipe `UioSlider` around the base slider) and `script_param_util.buildScriptParamCompSimple` (Lua copy of the local `ScriptParamSliderAndText`); off inside `SettingsPage` |
| Notifications | icons of the same kind grouped with a count | `notifications.lua` | Lua conversion of the base ridge (`notification_popups.tl`), replacing it |
| Notifications | subsidy icons coloured by state, timer ring opaque and amber/red as time runs out | `notifications.lua`, `notifications.css.lua` | as the ridge above; a state class around the base icon recipes |
| Subsidies | offer expiry ring and text, labelled time limit and time left, effect duration | `subsidies.lua` | patches `subvention_util.makeDefaultCardData` (GUI state only) |
| Finance window | income statement, cash flow, balance sheet next to the game's table | `finances.lua`, `core/statements.lua` | replaces the exported `FinancesTable` (finances_table.tl); *Details* calls the original |
| Map | passenger and cargo catchment areas of all stations, switched separately, saved with the game | `catchment.lua` | `react-plugin ::MainModButtonAreaExtension` (toggles); wraps `selector_react_util.makeDefaultSelectorCombinedFn` and, during its call, `builtin.ActionDescriptor` to add a `LayerConfig` |
| Game bar | Earnings tooltip with the cash flow of the last 30 days and the 30 days before | `earnings.lua` | replaces `GameBarEarningsPlugin` |
| Vehicle store | newest model first and preselected (list layout) | `store_tweaks.lua` | patches `react.useState` for the one sort state `{ mode = "YearFrom", ascending = true, groupTypes = true }` |

## Architecture

```
src/ui_overhaul/content/ui_overhaul/
  core/      pure Lua, no engine access; offline specs run against the mock engine
  engine/    snapshot.lua reads the game into plain tables; store.lua caches the snapshot
  gui/       one module per change, each with a .res.lua resource and a .script.lua stub
  logger.lua
```

### Guarded stubs

A mistake in a GUI mod can take the whole game UI down: an error that escapes a recipe, or a module that fails to load, makes the engine drop every screen. So the engine never sees the mod's modules directly. Each change has two small files:

- `<name>.res.lua` registers it, as a `react-plugin ::<ExtensionPoint>` or as a `react-replacement-config`.
- `<name>.script.lua` is the stub the resource points at. It loads the module through `guard.lua` with `pcall`.

For a plugin, the stub registers a recipe that renders `guard.plugin(path, field)`. If the module fails to load or the call raises an error, the recipe renders an empty `BoxLayout` and logs one `[ui_overhaul] disabled ...` line.

For a replacement, the stub's `doReplaceFn` calls the module's `install(replacement_api)` inside `pcall`. If that fails, nothing is replaced, the game keeps its vanilla screen and the stub logs one `[ui_overhaul]` line. A replacement recipe that fails while rendering falls back to the base recipe through `react.CallOriginalRecipe` (for example `notifications.lua`, which then keeps showing the base ridge for the session).

### Extension points, replacements and module-field wraps

The mod uses three kinds of hooks, in this order of preference:

1. Extension points (`react-plugin`). They add to a screen and conflict with nothing. The mod uses `::ModEntryPointExtension` for its invisible entry point and `::LineEowExtensionPoint` for the Stops card.
2. Wraps of module fields. Many base functions are called through their module table at run time (`construction_react_util.getMenuCategories`, `company_util.getConstructionDisableReason`, `popover_react_util.PopoverWindowContent`, `vehicle_react_util.HandleVehicleChanges`). Replacing the field with a function that calls the previous one changes the result without owning the recipe, and several mods can chain on the same field. The patches are installed from a `doReplaceFn`, before the UI starts.
3. Recipe replacements (`react-replacement-config`, `replacement_api.ReplaceRecipe`). Only one mod can replace a given recipe. A replacement calls the original recipe where it can (`lvm_rows.lua`, `tool_stack.lua`, `window_tweaks.lua`) and changes only what it must. Where the change sits inside the base recipe, the module is a Lua conversion of the base file registered under the base recipe names (the Statistics tabs, the notification ridge, the Earnings plugin, the line window's Vehicles card).

The README lists every recipe the mod replaces, so players can see which other mods conflict.

### Data and actions

- The entry point (`entry.lua`) is mounted for the whole session. It refreshes the shared snapshot in `engine/store.lua` every `store.REFRESH_SECONDS` (2 s), drives `defer.lua`, runs `cleanup.lua` (which ends persistent notifications of `ux_overhaul` types that the mod does not define), and owns the `uio.action` event that other mods and the testbench use.
- Widgets read engine data with `engine_react_util.useStepStateTimer`. Reads over a whole town or network use the parallel variants (`useStepStateParallelSimple`).
- Timer callbacks only read the engine. They must not call GUI-thread functions, including `_()`, so the snapshot holds untranslated base-game string keys and the GUI translates them when it renders. See [CONTRIBUTING.md](../CONTRIBUTING.md#rules-the-game-enforces).
- Actions go through the base game's own events and helpers where they exist (`duplicateVehicles`, `selectEntity{stack = true}`, `openVehicleManager`, `openStatisticsWindow`, `openFinanceWindow`), so the base checks for money, depots and mission locks apply. Otherwise they send `api.cmd.make*Cmd` with a callback. The mod respects `gameCtx.filters.protectedEntities`, so campaign missions keep working.
- Recipe names of the mod's own recipes start with `Uio`, events with `uio.`, and all variables are `local`. CSS selectors and event names are global and shared with other mods.
- `GameUIRoot`, `HudIconMasterGame` and `PerkHudIcon` are never replaced; campaign missions replace the last two.

### Testing

- Offline: specs for `core/` and `engine/` against the mock engine (`make test`).
- In game: `make test-ingame` starts the game with the testbench in `spec/ingame/ui_overhaul_testbench/`. Its GUI checks fire `uio.*` events and test `api.gui.byId.isVisibleRecursive("uio.…")` for PASS or FAIL. `spec/ingame/run.sh` also fails on `ReactFramework::Load() failed` and on React errors in `stdout.txt`.
- `api.gui.camera.takeScreenshot` renders without the UI, and `byId.getSize` returns 0×0 for anything that is not a window, so GUI checks use `byId.isVisible` and CSS-driven probes.
- Every text exists in all the game's languages (`en`, `de`, `fr`, `it`, `es`, `nl`, `ja`, `ko`, `pl`, `pt_BR`, `ru`, `zh_CN`, `zh_TW`, the game's own language folders; `tools/strings_check.py`).

The gates and how to check what players see are in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Engine rules

The rules that break the whole UI when ignored (layout roots, Lua 5.2, GUI-thread calls in timers, fully qualified `require` paths, `strings.json`) are in [CONTRIBUTING.md, "Rules the game enforces"](../CONTRIBUTING.md#rules-the-game-enforces). These rules shape individual features:

- The construction tool has no veto callback (`ConstructionActionParam`, `scripts/builtin.d.tl:1356-1380`), and `onProposalApply` fires after the change. A mod cannot show a confirmation before the bulldozer removes something, so the bulldozer warning lives in the proposal tooltip.
- `constructionMenuSetTab{sublistId}` passes the data index of a sublist where `setActiveTab` expects a shown position (`construction.tl:2809-2821`). In the dynamic Modules menu empty sublists are hidden, so the event opens the wrong tab or raises a Lua error. *Configure* therefore orders the module tabs so the target tab comes first.
- A construction menu with no entries disables its game-bar button (`constructionMenuCategoryEmpty`, `game_bar.tl:608-613, 631`). The merged menus mirror the other menu's entries instead of moving them, so both buttons stay active.
- Every menu key in `getMenuCategories` must stay a table: `ipairs(menuCategories[menu])` at `construction.tl:4012`.
- The game applies a promotion only when the Company window's rank view mounts (`company/company.tl:420-422`), while the game bar already shows the new rank. The mod names this in the lock reason. Applying the rank automatically would skip the game's unlock screen.
- Input actions are hard-coded in the engine, so a mod cannot add rebindable hotkeys.
- General undo, a parallel or double-track builder and timetables are out of reach for a GUI mod.
- Changing how list items render in the construction menu would mean forking the 5,000-line `construction.tl`.

## Compatibility with other mods

Community mods that use the same hooks:

- `celmi_timetables`
  - replaces `line_manager_panel.LineManagerPanel`;
  - adds plugins to the game bar, the mod button area, the radial menu, and the Line, Station and Vehicle windows.
  - UI Overhaul must not replace `LineManagerPanel`, which rules out changing the stop rows through that recipe. The Stops card uses its own `order` in the line window.
- `zhenya_auto_assign_terminals`
  - replaces `popover_react_util.PopoverWindowContent` and a scroll container;
  - patches `line_util.makeLineActionDescriptor` and `builtin.Button`.
  - UI Overhaul does not replace those recipes. The terminal buttons wrap the module field `popover_react_util.PopoverWindowContent`, which `PopoverWindow` looks up on each render, so Auto Assign Terminals keeps its replacement and sees the same parameters.
- `terminal_selector`
  - replaces `station_group.StationGroupWindowContent` with a copy that has a terminal button per line stop;
  - registers its own popover recipe under the name `TerminalSelection`, with parameters `lineEntity` and `stopIndex0`.
  - UI Overhaul swaps only a `TerminalSelection` popover with the Line Manager's parameters (`viaState`, `commonParams`), so this popover keeps its own content. The station buttons turn off while the station window is replaced (`_react.recipeReplace`), so no row has two buttons.
- `zhenya_easy_terminal_assignment`
  - wraps `popover_react_util.PopoverWindowContent` (order 100) and swaps every popover named `TerminalSelection` for its own.
  - UI Overhaul's popover is registered under that name, so Easy Terminal Assignment wins in either wrapping order. The popover that the station and line window buttons open has the Line Manager's parameters, and `commonParams.lineState:old()` returns the same table until a change, so its in-place edit before `changeMainTerminal` is kept.
- `auto_line_namer` has only `rename_scheme` data and a game script, so it does not conflict.

## Risks

- Game updates. The mod depends on internal module paths and exported recipes, which are not a public API. After a game patch, re-run `tools/extract_game_sources.sh` and diff the sources. Replacements stay few and call the original recipe where they can, and each stub falls back to the vanilla screen when its module fails.
- Mod conflicts. Only one mod can replace a given recipe; the one that registers last wins. The README lists the replaced recipes.
- Performance on large networks. Widgets read the engine on timers or through parallel state, and the shared snapshot is refreshed once for all of them.
- Savegames. The mod changes only the GUI and adds no game script, so it can be added to and removed from a savegame.
