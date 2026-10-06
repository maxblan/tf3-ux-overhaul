# UI Overhaul design

UI Overhaul changes the game's own screens so that players read the state of their network faster and act on it with fewer clicks. It works inside the vanilla Line Manager, Statistics, entity windows, construction menu, notification ridge and game bar. The code-level inventory of those screens is in [inventory/](inventory/README.md), and the ranked list of further changes is in [improvements.md](improvements.md).

## Design rules

1. Improve the game's own screens in place. A change should feel as if the game always worked that way.
2. Keep the vanilla look. Use the game's widgets and style classes. Replacement recipes are registered under the base recipe names, so the base stylesheet applies to them unchanged.
3. Nothing new for players to learn. The mod fills in figures, fixes sorting and removes clicks in places players already look.
4. Only information the game already shows somewhere. A figure may move to where it is needed (a vehicle's load in the Line Manager, as the vehicle window shows it), but what the game computes and never shows stays out: an industry's chance to expand, speeds on slopes, a cash flow statement or a balance sheet, measurements while building. New controls are fine where they cannot fire by accident: the mouse wheel moves a slider only where nothing around it scrolls.
5. New UI only when the goal cannot be reached inside an existing screen, and then in vanilla style. The Stops card in the line window and the model row above the Line Manager's vehicle list are of this kind.
6. No new notifications, and no change to which notifications the game shows or hides. The notification ridge groups icons of the same kind; which notifications exist is left to the game.
7. Gameplay screens only. Saving, loading, the pause menu and the main menu stay vanilla.
8. Actions that touch many vehicles at once ask first, in the game's own question prompt (clone, replace or modify several vehicles) or with a second click (Sell in the vehicle window). Single actions stay instant.

## What the mod changes

The player-facing list is in the [README](../README.md#what-changes). This table maps each change to its module in `src/ui_overhaul/content/ui_overhaul/gui/` and to the hook it uses.

| Screen | Change | Module | Hook |
|---|---|---|---|
| Line Manager | cargo icons, vehicle count and 12-month balance in line rows; age in vehicle rows | `lvm_rows.lua` | replaces `line_react_util.ManagerNotificationWidget`, calls the original |
| Line Manager | model row above the vehicle list, *In all lines*, Shift+click selects a model | `lvm_models.lua`, `lvm_tweaks.lua` | replaces `vehicle_list_react_util.VehicleList`; wraps the manager's `selectVehicles` |
| Line Manager | station click with several lines selected does not move their vehicles | `lvm_tweaks.lua` | wraps `commonParams.newLine` |
| Line Manager | confirmation before cloning, replacing or modifying more than one vehicle; reopening selects the last line | `lvm_tweaks.lua` | patches `react.fireEvent` (`duplicateVehicles`) and `vehicle_react_util.HandleVehicleChanges`; uses the tool stack's pop hook |
| Line Manager | *Select Terminals* with three buttons per terminal | `terminals.lua` | wraps the module function `popover_react_util.PopoverWindowContent`; swaps only a popover with the Line Manager's parameters |
| Station window | *Select Terminals* button for each line stop in the Terminals list | `station_terminals.lua`, `terminals.lua` | wraps the global `orderedPairs` and `gui_react_util.makeHorizontalSpacer` while the file-local recipe `TerminalStops` renders; off while another mod replaces the station window. With *Select Terminals* off the button opens the base popover: the base recipe once the Line Manager handed it over, else a line-by-line Lua conversion of it (`terminals.Vanilla`; the base recipe is file-local) |
| Line window | *Add Vehicle* and *Remove Vehicle* in the Vehicles card | `line_vehicles.lua` | replaces `line_eow.LineVehiclesPlugin` |
| Line window | Stops card, with a *Select Terminals* button per stop; unreachable stops greyed with the base problem text | `cards.lua`, `terminals.lua`, `core/line_problems.lua` | `react-plugin ::LineEowExtensionPoint`, `order = 55` |
| Line Manager | *Select Terminals*: preferred terminal highlighted, unusable or unreachable terminals greyed with the reason | `terminals.lua`, `core/line_problems.lua` | as *Select Terminals* above |
| Line Manager | add-stop hover names a missing path from the stop before or to the next | `lvm_tweaks.lua` | replaces `manager_tooltips_util.LMAddStop`; `api.engine.util.pathfinding.findPathNodeToNode` |
| Statistics | Lines, Vehicles and Stations tabs: quick filters, totals, sorting fixes | `statistics_lines.lua`, `statistics_vehicles.lua`, `statistics_stations.lua`, `statistics_common.lua`, `statistics_common.css.lua` (quick-filter bar, all four tabs) | Lua conversions of the base tabs, replacing them |
| Statistics | Warehouses tab: cargo icons with quantities, cargo picker that filters and sorts, quick filters, totals | `statistics_warehouses.lua` | Lua conversion of the base tab, replacing it |
| Windows | tool windows side by side, kept open on map clicks | `tool_stack.lua` | replaces `builtin.ToolStack` |
| Windows | minimize button in the title bar of every window with a title and a close button | `minimize.lua` | wraps `builtin.Window` (header slot: the title row with the title, an own rename field and the button, since the engine draws the header before its title; content: hidden by class while folded; windows of a `builtin.Window` wrapper recipe also get `uio-window-folded`, which drops the fixed height of Finances, Company and Statistics) and `react.RegisterWrapperRecipe` (window recipes registered later must still wrap the base builtin, or the game crashes); the Line Manager is a compact window without a title bar, so its title row (`_("Line Manager")`, the game bar's term, and the button) goes above its content, clear of the engine's close button at the corner (`COMPACT_TOOLS`) |
| Entity windows | sections stay open | `window_tweaks.lua` (`install_sections`) | wraps `content_card.makeContentCardsCollapsibleFunctions` (calls the previous one with `onlyOneExpandable = false` for sections, the caller's value for collapse-all) |
| Vehicle window | *Sell* needs a second click | `window_tweaks.lua` (`install_sell`) | a wrapper recipe (`react.RegisterWrapperRecipe`) around the recipe in `entity_window_util.ActionButtonBar`, put in that field; it changes only a bar with the vehicle window's Sell button and returns `react.CallOriginalRecipe` of the recipe below, as the engine requires of a wrapper (in pcall, no child on failure); where a mod replaced the bar below (`ReplaceRecipe`), it steps aside in the late config and logs it (`settle_sell`) |
| Map | vehicle hover tooltip: line, next stop, speed, load, condition, delivery quality | `vehicle_tooltip.lua`, `vehicle_info.lua` | replaces `game_tooltips.DefaultEntityToolTip`, calls the original |
| Line Manager, line window | load and condition in vehicle rows, the five figures in the tooltip | `lvm_rows.lua`, `line_vehicles.lua`, `vehicle_info.lua` | as the rows and Vehicles card above |
| Vehicle window | Performance card with the rating the vehicle store shows | `performance.lua` | `react-plugin ::VehicleEowExtensionPoint`, `order = 55`; the rating from `vehicle_util.getPowerRatingTextAndToolTip`, called as the store calls it |
| Industry window | Development card (recipes, level, share transported, blockers), Served by card (lines) | `industry_cards.lua`, `core/industry_development.lua` | `react-plugin ::IndustryEowExtensionPoint`, `order = 15` |
| Industry window | eye button shows or hides the red area of a blocked expansion | `industry_cards.lua` | replaces the exported `IndustryWindow` (calls the original with a wrapped `setActionFn`); wraps `builtin.LayerConfig` while that action renders to drop `plotsRenderableConfig` |
| Town window | growth bottleneck and progress to the next level as text | `window_tweaks.lua` (`install_town`) | patches `content_card.makeRecipeAndParam` while `TownLevelPlugin` renders |
| Construction | locked perk says *Promotion pending* | `window_tweaks.lua` (`install_promotion`) | patches `company_util.getConstructionDisableReason` (GUI state only) |
| Construction | merged Rail/Tracks and Road/Roads menus, fastest track first, module tab order | `construction.lua` | patches `construction_react_util.getMenuCategories` |
| Construction | bulldozer warning | `construction.lua` (`install_bulldozer_warning`) | patches `construction_react_util.getActionParams` (the bulldozer's tooltip lines) |
| Construction | settings panel and Settings window stay above the game bar at large scales | `construction.css.lua` | CSS: height limits in `vh`, bottom padding per text scale |
| Sliders | mouse wheel (only on sliders of the recipes in `WHEEL_IN`: construction parameters and the game bar; elsewhere the wheel scrolls), typed values | `sliders.lua`, `core/slider_values.lua` | wraps the module fields `builtin.Slider` (recipe `UioSlider` around the base slider) and `script_param_util.buildScriptParamCompSimple` (Lua copy of the local `ScriptParamSliderAndText`); the recipe rendering the slider decides about the wheel; off inside `SettingsPage` |
| Notifications | icons of the same kind grouped with a count | `notifications.lua` | Lua conversion of the base ridge (`notification_popups.tl`), replacing it |
| Notifications | icons of every type in darker shades of the game's colours (caution amber, problem red, info blue, achievement green, unknown grey; all ≥ 7:1 to white); subsidy icons coloured by state (blue/orange/green/red/grey, all ≥ 7:1 to white), timer ring plain white | `notifications.lua`, `notifications.css.lua` | as the ridge above; a state class around the base icon recipes |
| Subsidies | offer expiry ring and text, labelled time limit and time left, effect duration | `subsidies.lua` | patches `subvention_util.makeDefaultCardData` (GUI state only) |
| Finance window | income statement next to the game's table | `finances.lua`, `core/statements.lua` | replaces the exported `FinancesTable` (finances_table.tl); *Details* calls the original |
| Map | passenger and cargo catchment areas of all stations, switched separately, saved with the game | `catchment.lua` | `react-plugin ::MainModButtonAreaExtension` (toggles); wraps `selector_react_util.makeDefaultSelectorCombinedFn` and, during its call, `builtin.ActionDescriptor` to add a `LayerConfig` |
| Game bar | Earnings tooltip with the cash flow of the last 30 days and the 30 days before | `earnings.lua` | replaces `GameBarEarningsPlugin` |
| Vehicle store | newest model first and preselected (list layout) | `store_tweaks.lua` | patches `react.useState` for the one sort state `{ mode = "YearFrom", ascending = true, groupTypes = true }` |

## Architecture

```
src/ui_overhaul/content/ui_overhaul/
  core/      pure Lua, no engine access; offline specs run against the mock engine
  gui/       one module per change, each with a .res.lua resource and a .script.lua stub
```

### Installer, settings and the mod list

All features install from two react-replacement-configs (`installer_early.res.lua`, order -1e9, and `installer_late.res.lua`, order 1e9), so the mod's own order no longer depends on the `order` numbers other authors pick (the game sorts configs by `order` only, and equal orders in no fixed way):

- **Early, before every other mod's config** (`installer.lua`): `settings.lua` reads the player's switches (`api.engine.config.getModParams()`, the params in `mod.json`); a feature switched off is not installed at all. `priority.lua` learns the mods' activation order and starts recording which mod replaces which recipe. Then each feature installs: its wraps of module functions go in as the innermost link (`priority.chain`), its recipe replacements are only noted (`priority.replacement_api`).
- **Between the two** (`priority.ready`): the game's debug library has only `getinfo` and `traceback` (observed in game), so a chain of wraps cannot be followed through upvalues. Instead, from the end of the early config to the start of the late one, the function fields of every loaded module (modules loaded meanwhile included) and the registry of recipe replacements sit behind a metatable that logs each write and the mod on the stack that made it (`__pairs` still lists every field). The late step reads who wrapped which function, in which order, from that log, and puts every field back in place.
- **Late, after every other mod's config** (`priority.late`): for each feature, a mod that comes first in the mod list and replaces one of its recipes wins the whole feature (UI Overhaul's version stays off); otherwise the feature's replacements are applied over later mods'. A function that later mods wrapped too gets a second, outermost link, so UI Overhaul has the last word there; where a mod that comes first wrapped it, the inner link stays and that mod's wrap has the last word. Both changes stay in either case. Where mods on both sides wrap the same function, the inner link stays (the earlier mod has the last word over UI Overhaul; a later one may still wrap outside it, which only taking its wrap apart could change), and the log says so. A module whose install fails takes back what it did before the error (`priority.finish(false)`), so a feature of several modules keeps only the modules that installed in full.
- **Duplicates** (`priority.OVERLAPS`): mods whose GUI changes, as a whole, show the same thing as one feature without touching the same recipe or function. The one that comes first is shown. Where UI Overhaul comes first and the feature is shown, the other mod is held back in one general way, without knowing its internals: its writes at the end of each logged field are taken back (its recipe replacements, its wraps of module functions; a field it only added stays), so the replacement or function before it is used again, and its plugins are left out of every extension point (`react.getPlugins`). A write of it that a third mod wrapped again stays, and the log says so; so do changes to the globals, which are not logged (their table has a metatable of the game's). Where the other mod comes first, UI Overhaul's feature stays off. Only mods that change nothing else belong in the list; what such a mod does later, at render time, is out of reach.
- **Settled once** (`priority.late`, last step): each chained field is built anew from below, up to the first wrap of another mod: a link that runs its feature's wrap becomes the wrap itself (made again over what is now below it where that changed), a link of a feature that is off becomes the function it wrapped (`builtin.*` widget wraps included, `builtin_wraps.lua`). No call checks a setting or a decision afterwards. A link under another mod's wrap stays and still switches; the log names them.
- **Stylesheets** (`styles.lua`): the game runs the stylesheets once, before the replacement configs, in a Lua state of their own without `api.engine` (observed in game), so they can read neither the settings nor the load order. Every rule therefore selects something only this mod puts there while the feature is shown (`spec/gui/stylesheets_spec.lua` checks each one): its own classes and recipes, or, for the game's own elements in windows, the classes `uio-on-<feature>` (the feature is shown) and `uio-own-<feature>` (and no mod that comes first has the last word in it) that a wrap of `builtin.Window` gives every window once the order is decided. The notification icons of the mod's ridge lie in components of class `uio-notification-icon`.

How it knows the order and the owners (all observed in game, see [api_cookbook.md](api_cookbook.md#9-load-order-and-other-mods)): generic resource ids are handed out in activation order and resource names start with their mod id; `debug.getinfo` gives a function's source, `<mod id>::/path` for a module loaded with `require` and the file's path on disk for a resource script; the files of a mod lie under one folder, found from the functions of its replacement configs. Without the debug library UI Overhaul goes first, as before.

### Game updates

The base modules are no public API, and the game is still being patched. Two guards keep a patch from taking a screen down with it:

- **At load** (`compat.lua`): `tools/needs.py` (run by `make content`, checked by CI) writes `needs.lua`, the fields every GUI module reads from each base module, the mod's modules each one requires and the modules each feature's plugins render. Before a feature installs, the installer checks the game still has every one of them; if not, the feature stays vanilla and one log line names what is missing. The log's first line names the game build.
- **At render time** (`guard.base`): a replacement calls the base recipe it replaced through the recipe the base module held when the mod loaded, in `pcall`, and renders an empty layout where the original makes no node or raises. The field at render time may hold another mod's plain function, which `react.CallOriginalRecipe` does not know as a recipe.

The check is per module: features that share a module (the four of `window_tweaks.lua`, the two of `construction.lua`) stay vanilla together when that module misses a field. It does not follow the mod's infrastructure modules (priority, guard ...: without them nothing installs) nor modules loaded with `guard.module`, which are optional where they are used (the Stops card's terminal button). A base module that is a recipe itself only has to load.

What neither catches: a base recipe that keeps its name and changes what it does. The Lua conversions of base recipes (the Statistics tabs, the notification ridge, the Earnings plugin, the line window's Vehicles card) then show the old behaviour until they are converted again. After a game patch, re-run `tools/extract_game_sources.sh`, diff the sources of those recipes, and run `make test-ingame`.

### Guarded stubs

A mistake in a GUI mod can take the whole game UI down: an error that escapes a recipe, or a module that fails to load, makes the engine drop every screen. So the engine never sees the mod's modules directly:

- `installer.script.lua` is the stub of both installer configs; it loads `installer.lua` through `guard.lua` with `pcall`, and the installer runs each feature's `install` in `pcall`. If one fails, nothing of it is replaced, the game keeps its vanilla screen and one `[ui_overhaul]` line is logged.
- Plugins (`<name>.res.lua` as `react-plugin ::<ExtensionPoint>`) point at a stub in `<name>.script.lua` that registers a recipe rendering `guard.plugin(path, field, feature)`. It renders an empty `BoxLayout` while the feature is not shown (switched off, or given up to a mod that comes first), and logs one `[ui_overhaul] disabled ...` line if the module fails to load or the call raises an error.

### Extension points, replacements and module-field wraps

The mod uses three kinds of hooks, in this order of preference:

1. Extension points (`react-plugin`). They add to a screen and conflict with nothing. The mod uses `::ModEntryPointExtension` for its invisible entry point and `::LineEowExtensionPoint` for the Stops card.
2. Wraps of module fields. Many base functions are called through their module table at run time (`construction_react_util.getMenuCategories`, `company_util.getConstructionDisableReason`, `popover_react_util.PopoverWindowContent`, `vehicle_react_util.HandleVehicleChanges`). Replacing the field with a function that calls the previous one changes the result without owning the recipe, and several mods can chain on the same field. The patches are installed from a `doReplaceFn`, before the UI starts.
3. Recipe replacements (`react-replacement-config`, `replacement_api.ReplaceRecipe`). Only one mod can replace a given recipe. A replacement calls the original recipe where it can (`lvm_rows.lua`, `tool_stack.lua`, `window_tweaks.lua`) and changes only what it must. Where the change sits inside the base recipe, the module is a Lua conversion of the base file registered under the base recipe names (the Statistics tabs, the notification ridge, the Earnings plugin, the line window's Vehicles card).

The README lists every recipe the mod replaces, so players can see which other mods conflict.

### Data and actions

- The entry point (`entry.lua`) is mounted for the whole session. It runs `cleanup.lua` (which ends persistent notifications of `ux_overhaul` types that the mod does not define), keeps a copy of the mission's protected entities for `actions.lua`, and owns the `uio.action` event that other mods and the testbench use.
- There is no shared snapshot of the network. Each widget reads only what it shows, while it is shown.
- Widgets read engine data with `engine_react_util.useStepStateTimer`. Reads over a whole town or network use the parallel variants (`useStepStateParallelSimple`).
- Timer callbacks only read the engine. They must not call GUI-thread functions, including `_()`, so they return untranslated base-game string keys and the GUI translates them when it renders. See [CONTRIBUTING.md](../CONTRIBUTING.md#rules-the-game-enforces).
- Actions go through the base game's own events and helpers where they exist (`duplicateVehicles`, `selectEntity{stack = true}`, `openVehicleManager`), so the base checks for money, depots and mission locks apply. Otherwise they send `api.cmd.make*Cmd` with a callback. The mod respects `gameCtx.filters.protectedEntities`, so campaign missions keep working: every path that sells a vehicle checks it first, from the window's `gameCtx` or, for the `uio.action` event, from the copy the entry point keeps from the same `setProtectedEntities` event. The reasons the game gives for refusing (money, mission lock, protected vehicle, depot) appear in the window's feedback list, as in the vehicle window; without a window they go to the game log.
- Recipe names of the mod's own recipes start with `Uio`, events with `uio.`, and all variables are `local`. CSS selectors and event names are global and shared with other mods.
- `GameUIRoot`, `HudIconMasterGame` and `PerkHudIcon` are never replaced; campaign missions replace the last two.

### Testing

- Offline: specs for `core/` and for the engine-free parts of `gui/` against the mock engine (`make test`).
- In game: `make test-ingame` starts the game with the testbench in `spec/ingame/ui_overhaul_testbench/`. `ONLY="…"` runs just the named checks, which makes bisecting a native crash a matter of minutes. Its GUI checks fire `uio.*` events and test `api.gui.byId.isVisibleRecursive("uio.…")` for PASS or FAIL. `spec/ingame/run.sh` also fails on `ReactFramework::Load() failed` and on React errors in `stdout.txt`.
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
- A wrapper recipe (`react.RegisterWrapperRecipe(name, wrapped, fn)`) must return a node of exactly the recipe it wraps (`react.lua`, `checkRecipeMatch`); anything else raises "Wrapper recipe must return child" on every render, and the window freezes. So a recipe another mod may wrap this way must not be replaced: replacing it makes the plain call inside their wrapper return the replacement. Where the mod only changes a recipe's params, it wraps it the same way instead, and makes its child with `react.CallOriginalRecipe` of the recipe below, so it fits whatever lies there. Observed with Warehouse Station Coverage, which wraps `entity_window_util.ActionButtonBar` (2026-10).

## Compatibility with other mods

The rule: where UI Overhaul and another mod change the same part, the one that comes first in the mod list wins (see Installer, settings and the mod list above). Tested in game (`make test-ingame SAVE=... WITH=... [MODS_FIRST=1]`) with these mods, in both orders:

| Mod | What it changes | Shared part | Result |
|---|---|---|---|
| `celmi_timetables` (Timetables) | replaces `LineManagerPanel`; plugins in the game bar, mod buttons, radial menu, line, station and vehicle windows | none | both work |
| `zhenya_auto_assign_terminals` | replaces `PopoverWindowContent` and `ContentWidgetScrollContainer`; wraps `line_util.makeLineActionDescriptor`, `makeNewStop`, `builtin.Button` | the terminal popover | both work: UI Overhaul wraps the module field `PopoverWindowContent`, which is called before the replaced recipe |
| `terminal_selector` | replaces `StationGroupWindowContent` (a copy with terminal buttons), wraps `react.CallOriginalRecipe` | station window terminal buttons | first in the list wins (OVERLAPS) |
| `tcoleman_financial_statements_1` | replaces `FinancesTable` | the Finances table | first in the list wins |
| `gleisbauanzeige_tf3` (Track & Road Build Info) | wraps `construction_react_util.getActionParams` (build tooltip lines) | `getActionParams`, which the bulldozer warning wraps too | both work, both wraps nested by the list (tested while UI Overhaul still had build measurements of its own, then held back as a duplicate; those are gone) |
| `cayde_industry_enhanced_1` (Industry UI Enhanced) | two industry window plugins (details with the expansion footprint on the map, lines); replaces the `builtin.LayerConfig` recipe to add the footprint | industry window cards | first in the list wins (OVERLAPS): where UI Overhaul comes first, its cards, footprint included, are held back; move it above UI Overhaul for them. Its footprint survives UI Overhaul's red-area switch (that strips the plots in the `builtin.LayerConfig` field, it adds its own after) |
| `warehouse_coverage_probe_1` (Warehouse Station Coverage) | a wrapper recipe around `entity_window_util.ActionButtonBar` (Extra Coverage checkbox in the warehouse window), game bar and warehouse window plugins | the action bar | both work in either order since UI Overhaul wraps the bar too; before, its replacement of the bar broke their wrapper (every entity window froze) |
| `apasz_dark_ui_1` (Dark UI) | game colours (`default_colors.gres.lua`), CSS | none | both work |
| `auto_line_namer_1`, `auto_signals_1`, `parallel_tracks_1`, `parallel_roads_1`, `mc_realistic_brk`, `tunnel_portal_fix_1` | game scripts, data | none | both work |
| `zhenya_easy_terminal_assignment` | wraps `PopoverWindowContent` (order 100) and swaps every popover named `TerminalSelection` | the terminal popover | first in the list wins: UI Overhaul's popover has a name of its own (`UioTerminalPopover`) where it comes first, and the base name where Easy Terminal Assignment does (not tested in game: the mod was not installed) |

## Risks

- Game updates. The mod depends on internal module paths and exported recipes, which are not a public API. A feature whose base fields are gone stays vanilla (Game updates above); after a game patch, re-run `tools/extract_game_sources.sh`, diff the sources and run the in-game checks. Replacements stay few and call the original recipe where they can, and each stub falls back to the vanilla screen when its module fails.
- Mod conflicts. Only one mod can replace a given recipe. Which one is decided by the mod list (priority.lua), not by the config order; a mod that replaces a recipe at render time or after the late config (order above 1e9) is out of its reach. Duplicates that share no recipe or function are only recognised for the mods in `priority.OVERLAPS`; for others the player can switch the feature off.
- Performance on large networks. Widgets read the engine on timers or through parallel state, and only while they are shown; nothing reads the whole network in the background.
- Savegames. The mod changes only the GUI and adds no game script, so it can be added to and removed from a savegame.
