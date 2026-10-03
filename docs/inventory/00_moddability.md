# 00 — How a TF3 mod can change or extend the GUI (moddability)

Sources: extracted game source under `SCR/game/` (SCR = this scratchpad), official mods/DLC from
`.../Transport Fever 3/mods/release/*` and `dlcs/*` (extracted to `SCR/modsx/`), `strings TransportFever3.exe`
(saved as `SCR/exe_strings.txt`), the tf3-modding skill references, and `/mnt/c/Users/maxbl/tf3-mod-template`.
Paths below are relative to `SCR/game/gui/gui/` unless they start with another top-level folder.
"Verified" = shown in the code. "Needs in-game verification" = it follows from the code but nobody has run it yet.

## TL;DR: architecture decision

The whole in-game GUI is a Lua/Teal "React-like" recipe tree (`main/react.lua`). The engine renders C++ builtins.
It has **no imperative widget API** like TPF2's `api.gui.comp.*`. `api/gui.d.tl` has no constructors for widgets.
A mod has three official, data-driven hooks, all registered as **generic resources** (`*.res.lua` with `data()`).
Official Urban Games content uses all three:

| Mechanism | Resource `type` | Effort / risk | Use for |
|---|---|---|---|
| Plugin into an extension point | `"react-plugin <modId>::<ExtensionPointName>"` (base: `"react-plugin ::Name"`) | easy, additive, compatible with other mods | new widgets in entity windows, game bar, radial menu, mod button area, invisible "entry point" components (event/hotkey handlers that open your own windows) |
| Global recipe replacement | `"react-replacement-config"` → `doReplaceFn(replacementApi)` → `replacementApi.ReplaceRecipe(orig, repl)` | medium, **one winner per recipe**, breaks on game updates | changing/wrapping existing UI (LVM, statistics, game bar, EOW internals), as long as the recipe is **exported** by its module |
| Generic data resources | `menu_category`, `menu_filter_category`, `construction_tool`, `notification`, `rename_scheme`, `gui_res`... | easy | construction-menu categories, notification types, colours |

**File shadowing (shipping `gui/main/game.tl` in a mod) does not work.** No evidence for it was found; see §2.3.
**New rebindable hotkeys cannot be registered from Lua.** The input actions are hard-coded in the engine; see §3.3.

Recommended UX-mod architecture:
1. **Headless entry point**: a plugin into `::ModEntryPointExtension`. It listens to events and input actions, holds shared state and opens the mod's own windows or tools through `game_react_globals`.
2. **Visible launchers**: plugins into `::MainModButtonAreaExtension` (buttons next to the layer ridge, plus an automatic "Mods" entry in the radial menu) and `::GameBarInfoDisplayExtension` (always-visible status widgets in the game bar).
3. **Context panels**: plugins into the 14 entity-window extension points, for quick actions and status inside Line, Vehicle, Station, Industry and Town windows.
4. **Overrides** only where needed, through `react-replacement-config`. Always wrap with `react.CallOriginalRecipe` instead of rewriting, so the mod survives game updates better.
5. Data comes from `api.engine.*` / `api.engine.util.*` / `api.engine.system.*` in recipes, polled with `engine_react_util.useStepStateTimer`. Actions use `api.cmd.sendCommand(api.cmd.make*Cmd(...), callback)`. Callbacks work on the GUI side.

---

## 1. React plugins into existing extension points

### 1.1 Runtime (verified)

- `react.RegisterExtensionPoint(modId, name)` builds the id `modId .. "::" .. name` and marks it in `_react.extensionPoints` (`main/react.lua:67-77`). Base files pass `getOwningModId()`, which is `""` for the base game, so base ids look like `::LineEowExtensionPoint`.
- `RegisterWrapperExtensionPoint(modId, name, wrappedRecipeFn)` (`main/react.lua:79-90`) works the same way, but plugins **must return exactly 0 or 1 node of the wrapped builtin**. This is checked in `main/react.lua:280-293`. Example: the radial menu requires `builtin.RadialMenuChild`.
- `getPlugins(ep)` (`main/react.lua:92-118`) does the following:
  - `api.res.genericRep.getAllOfType("react-plugin " .. ep.id)`;
  - reads `genericRes.data` for each resource;
  - `util.useFn(desc.filePath)` loads the recipe function from `"<res path>@<field>"` (`scripts/scripts/util.tl:5-29`);
  - the optional `desc.condition` is loaded the same way;
  - plugins are sorted by `desc.order` (missing = 0, ascending).
- `gui_react_util.usePlugins(ep, detail, ...params)` (`main/gui_react_util.tl:513-567`):
  - filters with `condition(...params)`;
  - can interleave hard-coded nodes via `detail.insertHardcoded[order]`;
  - passes focus refs (`firstRef`/`lastRef`);
  - calls `recipe(...params)` and returns the nodes the host inserts.
- Descriptor type: `ReactPluginDesc { filePath : ResName, condition : ResName, order : number }` (`scripts/scripts/react.d.tl:405-409`).
- Pitfall: the two game-bar plugins set `priority = -2/-1` (`game_bar/game_bar_display_earnings_plugin/game_bar_display_earnings.res.lua:6`), but `getPlugins` only reads `order`, so both effectively have order 0. `table.sort` is not stable, so plugins with equal `order` come in **undefined order**. Always set an explicit `order`.

### 1.2 What a mod ships (pattern copied from base plugins)

A base plugin is a triple of files that sit next to each other: `*.res.lua` (descriptor), `*.script.tl` or `*.script.lua` (module that returns a table of recipes) and an optional `*.css.lua` (styles). Example: `game_bar/game_bar_display_earnings_plugin/{game_bar_display_earnings.res.lua, .script.tl, .css.lua}`.

```lua
-- content/<dir>/my_line_panel.res.lua   (any folder; the mission mods use mission/, the base uses gui/...)
function data()
  return {
    type = "react-plugin ::LineEowExtensionPoint",               -- "react-plugin " .. extension point id
    data = {
      filePath  = "<modId>::/<dir>/my_line_panel.script@MyLinePanel",   -- <module path without .lua/.tl>@<field>
      condition = "<modId>::/<dir>/my_line_panel.script@isPlayerOwned", -- optional fn(params) -> boolean
      order     = 25,                                            -- base Line EOW: 0 notification, 10 colour, 20 basics, ... 60 income
    },
  }
end
```
```lua
-- content/<dir>/my_line_panel.script.lua   (a plain module: it RETURNS A TABLE, no data(); same as base .script.tl files)
local react   = require "::/gui/main/react.lua"
local builtin = require "::/gui/main/builtin.lua"
local line_eow = require "::/gui/entity_window/line/line_eow.script.tl"
local M = {}
M.MyLinePanel = react.RegisterPluginRecipe(line_eow.LineEowExtensionPoint, "MyLinePanel", function(params)
  -- params: entityId, gameCtx, ownershipState, showCalloutOnRightSide, set/getCollapsibleExpanded, ...
  return builtin.TextView{ text = "Line " .. tostring(params.entityId) }
end)
function M.isPlayerOwned(params) return params.ownershipState == "Player" end
return M
```
- The module is loaded lazily at the first `getPlugins` call (`main/react.lua:102`). It runs in the GUI react Lua state (`Lua_React_Game` in the exe strings).
- `getOwningModId()` is injected per file (exe string near line 909885 of `exe_strings.txt`), so a mod can also **define its own extension points** with `react.RegisterExtensionPoint(getOwningModId(), "X")`. Other mods can then target them as `react-plugin <modId>::X`.
- Styles: `*.css.lua` returns a rule table built with `require "::/gui/main/stylesheetutil.lua"`. Selectors such as `"R::<RecipeName> BoxLayout"` target recipes by name (`game_bar/game_bar_display_earnings_plugin/game_bar_display_earnings.css.lua:8-15`). Whether a mod's `.css.lua` is picked up automatically, as the base ones are (`StyleSheetRep`, `loadStyleSheet` modifier in the exe), **needs in-game verification**.
- Note: the existing official mods contain **no `react-plugin`**. Only the base game uses them (54 `.res.lua` files). The mechanism is generic, though: any resource whose `type` matches is returned by `getAllOfType`. The official mission mods prove that mod `.res.lua` files enter the same `genericRep` (see §2). Plugin discovery from a staging mod **needs in-game verification**, but it is low risk.

### 1.3 Complete list of extension points

18 extension points are defined (4 global, 14 in entity windows), and all of them are consumed; 5 have no base plugins. Columns: definition file:line → `usePlugins` call site (file:line) → param type → where it renders.

| Id | Defined | Consumed | Params passed to plugin/condition | Where in the UI | Base plugins |
|---|---|---|---|---|---|
| `::ModEntryPointExtension` | `main/mod_entry_point.tl:5` | `main/game.tl:83` (recipe `EntryPoints`, mounted at `main/game.tl:573-586`, `class="invisible"`, localKey `internal-hidden`) | none (Extension0) | **Invisible** top-level container in `GameUIRoot`, next to the base `StatisticsEntryPoint`, `ManagerEntryPoint` and `VehicleStoreEntryPoint`. Intended for headless components: `react.onEvent`, `react.useInputAction`, pushing tools, adding windows | none |
| `::MainModButtonAreaExtension` | `main/main_mod_button_area.tl:7` | `main/main_mod_button_area.tl:13` (recipe `MainModButtonArea`, mounted at `main/game.tl:554` inside the `layer-buttons-ridge` box, `main/game.tl:529-556`) | none | Horizontal scroll strip right of the **layer button ridge**. If at least one plugin exists, the radial menu also gets a "Mods" entry that focuses this area (`main/game.tl:378-386`, `game_bar/game_bar.tl:170-180`) | none |
| `::RadialMenuExtension` (wrapper of `builtin.RadialMenuChild`) | `main/radial_menu_extension.tl:6` | `game_bar/game_bar.tl:54`, appended at `game_bar/game_bar.tl:183` | none; must return one `builtin.RadialMenuChild{icon, getInfoText, onActivate}` | Main radial menu (gamepad, `mouseSupport=true`) | none |
| `::GameBarInfoDisplayExtension` | `game_bar/game_bar_widgets.tl:70` | `game_bar/game_bar_widgets.tl:72` (recipe `GameBarInfoDisplay`, placed at `game_bar/game_bar.tl:1061`) | none | Horizontal scroll strip in the **game bar** (always visible) | Earnings, Transported (`game_bar/game_bar_display_*_plugin/*.res.lua`) |
| `::LineEowExtensionPoint` | `entity_window/line/line_eow.script.tl:24` | `entity_window/line/line.tl:132` | `LineEow.LineWidgetPluginParams` (`entity_window/line/line_eow.d.tl:4`) = `IEowWidgetsExtensionParams` | Line entity window, scroll content | 6: notification 0, colour picker 10, basics 20, transported graph, vehicles, income graph 60 |
| `::VehicleEowExtensionPoint` | `entity_window/vehicle/vehicle_eow.script.tl:24` | `entity_window/vehicle/vehicle.tl:246` | `VehicleWidgetPluginParams` + `state : VehicleEowState` (`vehicle_eow.d.tl:17`) | Vehicle window | 4: notification, basics, condition, balance |
| `::IndustryEowExtensionPoint` | `entity_window/industry/industry_eow.script.tl:23` | `entity_window/industry/industry.tl:300` | `IndustryWidgetPluginParams` + `state` (`industry_eow.d.tl:24`) | Industry window | 5: notification, production rules, boosters, stocks, balance chart |
| `::TownEowExtensionPoint` | `entity_window/town/town_eow.script.tl:19` | `entity_window/town/town.tl:1272` (with `insertHardcoded`) | `TownWidgetPluginParams` + `state` (`town_eow.d.tl:10`) | Town window, Overview tab | 5: notification, level, charts, map-editor supplies, debug graph |
| `::TownEowEditorExtensionPoint` | `entity_window/town/town_eow.script.tl:20` | `entity_window/town/town.tl:1289` | `TownEditorWidgetPluginParams` (`town_eow.d.tl:13`) | Town window, **editor tab** (the tab only appears when it has plugins) | 4 (sandbox only) |
| `::PerkEowExtensionPoint` | `entity_window/perk/perk_eow.script.tl:12` | `entity_window/perk/perk.tl:109` | `PerkWidgetPluginParams` + `state` | Perk/company building window | 6 |
| `::WarehouseEowExtensionPoint` | `entity_window/warehouse/warehouse_eow.script.tl:12` | `entity_window/warehouse/warehouse.tl:58` | `WarehouseWidgetPluginParams` + `state` | Warehouse window | 2: stocks, diagram |
| `::MaintenanceStationEowExtensionPoint` | `entity_window/maintenance_station/maintenance_station_eow.script.tl:13` | `entity_window/maintenance_station/maintenance_station.tl:76` | `MaintenanceStationWidgetPluginParams` + `state` | Maintenance-station window | 4: pool, balance, vehicles, statistics |
| `::SimPersonEowExtensionPoint` | `entity_window/sim_person/sim_person_eow.script.tl:12` | `entity_window/sim_person/sim_person.tl:135` | `SimPersonWidgetPluginParams` + `state` | Person (citizen) window | 3: locations, happiness, route |
| `::StationGroupEowExtensionPoint` | `entity_window/station_group/station_group_eow.script.tl:7` | `entity_window/station_group/station_group.tl:864` | `StationGroupWidgetPluginParams` (`station_group_eow.d.tl:4`) | **Station** window | **none (free slot)** |
| `::TownBuildingEowExtensionPoint` | `entity_window/town_building/town_building_eow.script.tl:5` | `entity_window/town_building/town_building.tl:334` | `TownBuildingWidgetPluginParams` | Town-building window | none |
| `::EmptyConstructionEowExtensionPoint` | `entity_window/empty_construction/empty_construction_eow.script.tl:7` | `entity_window/empty_construction/empty_construction.tl:37` | `EmptyConstructionWidgetPluginParams` | Empty construction-slot window | 1: notification |
| `::FunElementsEowExtensionPoint` | `entity_window/fun_elements/fun_elements_eow.script.tl:9` | `entity_window/fun_elements/fun_elements.tl:43` | `FunElementsWidgetPluginParams` | Fun-element window | 1: state |
| `::AnimalEowExtensionPoint` | `entity_window/animal/animal_eow.script.tl:8` | `entity_window/animal/animal.tl:44` | `AnimalWidgetPluginParams` | Animal window | 1: state |

Shared EOW params (`entity_window/eow_extension_util.d.tl:3-22`):
- `entityId`, `ownershipState` (`"None"|"Player"|"Foreign"`), **`gameCtx : GameContext`**;
- `showCalloutOnRightSide`, `setCollapsibleExpanded`, `getCollapsibleExpanded`;
- `firstWidgetRef`, `lastWidgetRef`.

Reusable helper: `eow_extension_util.useOwnershipStepState(entity)`.

**No extension points** exist in the line/vehicle manager (`line_vehicle_mgmt/manager_window.tl`, about 8500 lines), the vehicle store, the statistics windows (`statistics/*`), the finance and company windows, the construction menu (that one is driven by `menu_category` and `construction_tool` resources), the notification log, the HUD or the main menu. Changing those requires recipe replacement (§2).

---

## 2. Global recipe replacement and file shadowing

### 2.1 Mechanism (verified, used by official content)

- Each recipe function is a wrapper that checks `_react.recipeReplace[recipeId]` on every call (`main/react.lua:382-388`). The original is kept in `_react.originalRecipeFn` (`main/react.lua:380`).
- `GloballyReplaceRecipeBeforeInitInternal(orig, repl)` (`main/react.lua:445-455`) is ignored with a warning once `_react.recipeReplacementAllowed == false`. That flag starts as `true` (`base/base/init.lua:51`).
- `react.CallOriginalRecipe(replacedFn, ...)` (`main/react.lua:457-465`) calls the original. It is **not allowed for builtins** (`main/react.lua:459-461`).
- **The supported entry point is a generic resource, not a direct call.**
  - `bootstrap_game.tl:12-36` collects all `"react-replacement-config"` resources, sorts them by `order` and loads `filePath .. "@" .. doReplaceFn`.
  - `doReplacements()` (`main/bootstrap_game.tl:38-51`) calls each `doReplaceFn({ ReplaceRecipe = ... })` and **then sets `recipeReplacementAllowed = false`**.
  - It is exported as the global `_reactDoReplaceRecipes` (`main/bootstrap_game.tl:53`). The engine calls it (`_reactDoReplaceRecipes` is in the exe strings) after loading `::/gui/main/game.lua` → `bootstrap_game.tl` (`main/game.lua:1-5`) and before recipes execute.
  - Timing problem solved: a mod never has to race the bootstrap. It ships the config resource.
- Types: `ReactReplacementConfigDesc { filePath, doReplaceFn : string, order }` and `ReactReplacementApi.ReplaceRecipe(orig, repl)`, with the comment "replacement must be fully compatible, e.g. if the original provides an Api, the replacement must provide the same one" (`scripts/scripts/react.d.tl:422-437`).
- **Official examples:**
  - `urbangames_campaign_mission_01::/mission/hud_replacement.{res.lua,script.tl}` replaces `hud_icon_toolbox.HudIconMasterGame`;
  - missions 03, 05 and 07 ship `perk_icons_replacement.*`, which replaces `hud_icon_toolbox.PerkHudIcon`.

  Both register a new recipe **under the same name** and wrap `react.CallOriginalRecipe(...)` in a `BoxLayout` (`SCR/modsx/urbangames_campaign_mission_01/mission/mission/hud_replacement.script.tl:6-17`):
```lua
-- hud_replacement.res.lua
function data() return { type = "react-replacement-config",
  data = { filePath = "urbangames_campaign_mission_01::/mission/hud_replacement.script", doReplaceFn = "doReplaceFn" } } end
-- hud_replacement.script.tl
local Repl = react.RegisterRecipe("HudIconMasterGame", function(params, userParam)
  if game_react_globals.getDisableFeatures()["HudIconMaster"] then return nil end
  return builtin.BoxLayout{ children = { react.CallOriginalRecipe(hud_icon_toolbox.HudIconMasterGame, params, userParam) } }
end)
return { doReplaceFn = function(api) api.ReplaceRecipe(hud_icon_toolbox.HudIconMasterGame, Repl) end }
```

### 2.2 Constraints and risks

- **Only exported recipes can be replaced.** `GetRecipeId` needs the function object (`main/react.lua:438-440`), and `recipeFnToRecipeId` is local to react.lua.
  - Across `gui/`, **269 recipes are exported** (assigned to a module table) and **451 are `local`**. Local recipes are unreachable; replace their nearest exported parent instead.
  - The official mod reuses the same recipe *name* without collisions, so `makeRecipeId(name)` cannot be a pure function of the name. Ids cannot be forged.
- Important exported recipes:
  - `game_bar.GameBar`, `game_bar.MainRadialMenu`, `game_bar_widgets.*`;
  - `view_manager.ViewManager`, `make_entity_window.ConstructionWindow`;
  - `manager_window.ManagerWindowContent`, `manager_window.ManagerEntryPoint`;
  - `vehicle_list_react_util.VehicleList`, `line_react_util.*` (LineBalance, LineTransported, LineCargoDisplay, ...), `vehicle_react_util.*`;
  - `statistics.StatisticsEntryPoint`, `statistics_react_util.ProblemsCell`;
  - all `*_eow.script` plugins, which are also replaceable;
  - `hud_icon_toolbox.*`.
- **One replacement per recipe, last one wins.** `_react.recipeReplace[recipeId] = repl` overwrites (`main/react.lua:454`). `CallOriginalRecipe` always calls the base original, not the previous replacement, so two mods replacing the same recipe cannot chain. They conflict silently, and the outcome depends on `order` and load order.
- `GameUIRoot` and `GameUIProxyRoot` must exist exactly once and must not be replaced (`main/game.tl:114-117`, `main/game.tl:737-738`).
- A replacement must keep the original's signature and `provideApi` contract (`scripts/scripts/react.d.tl:423-425`). Wrapper recipes must return 0 or 1 child of the wrapped type (`main/react.lua:284-291`).
- Replacing large recipes (for example `ManagerWindowContent`) means copying base code. Every game update can break it, so prefer wrapping with `CallOriginalRecipe` plus additions.

### 2.3 File shadowing: not available (no evidence)

- Resources are namespaced as `<modId>::/path`, `::/path` = base, and `/path` = the owning mod. `require` resolves through the C++ `resolveutil.resolve(path, currentPath)` (`base/base/init.lua:62-105`). The resolved path is cached in `_ug_loadedModules`.
- Base GUI files import each other as `"::/gui/..."` or as owner-relative `"/gui/..."`, which resolves to base because base owns them. A file at `<myMod>::/gui/main/game.tl` is therefore a *different* resource, and nothing redirects base imports to it.
- The exe strings show no override, shadowing or "replaces base file" strings. They do contain `addFileFilter`/`applyFileFilters` (init.lua globals) and the modifier hooks.
- Conclusion: **do not rely on file shadowing.** It is TPF2 behaviour and does not follow from TF3's namespaced loader. *Needs in-game verification* if anyone wants to try.
- Untested alternatives found in the exe:
  - `addModifier("loadGameRes", fn)` from a mod `runFn`. It could rewrite base generic resources, for example change the `order`/`condition` of a base `react-plugin` resource or redirect its `filePath` to a mod recipe. Ref: skill engine.md §4 and the exe strings `loadGameRes`, `loadScript`, `loadStyleSheet`.
  - `api.gui.genericRep` exposes the type `"gui_res_overwrite"` (`apidef/api/gui.d.tl:1003-1008`; exe string `gui_res_overwrite`). Base content never uses it, and its schema is unknown. **Both need in-game verification.**

---

## 3. New windows, panels, toolbar buttons, hotkeys

### 3.1 Windows and panels

- Window container API (`scripts/scripts/builtin.d.tl:1216-1232`):
  - `addSingletonWindow(recipe, params)`, `addWindow(recipe, key, params)`;
  - `moveSingletonWindowToFront`, `removeAllWindows`, `removeWindow`.
- The window recipe is `builtin.Window` (`builtin.d.tl:1234`). All builtins (`main/builtin.lua`):
  - **containers and layouts:** Component, BoxLayout, FlowLayout, FloatingLayout(+Child), AbsoluteLayout(+Child), TableLayout, Row, ScrollArea, TabWidget(+Child), Window, WindowContainer(Delegate), ToolStack;
  - **tables, charts and lists:** DataTable(+Cell, ColumnDesc), Chart/Series, List;
  - **inputs:** Button, ToggleButton(Group), CheckBox, ComboBox, Slider, DoubleSpinBox, TextInputField, ColorPicker/ColorChooser;
  - **text and images:** TextView, RichTextView, ImageView, ProgressBar;
  - **game views and map overlays:** RadialMenu(+Child), LineRenderView, LineViewer, EntityRendererComponent, HudIconChildConfig, Selector, LayerConfig;
  - **tooltips and key hints:** ActionTooltip, KeybindingHintDisplay.
- Access from a mod: `require "::/gui/main/game_react_globals.tl"` (the same file the official mission mod uses).
  - It provides `getDefaultWindowApi()`, `getDefaultToolStackApi()`, `getDefaultRendererComponent()` and `getDisableFeatures()` (`main/game_react_globals.tl:9-30`, `main/game_react_globals.d.tl`).
  - **`GameContext` is not exposed there.** Extension0 plugins (ModEntryPoint, MainModButtonArea, GameBar) get no `gameCtx`; only EOW plugins receive it in params.
  - Workarounds: (a) open base windows by firing their events (§3.2), which the base entry points handle with their own `gameCtx`; (b) capture `gameCtx` from an EOW plugin or from a wrapper replacement of a recipe that receives it (e.g. `game_bar.GameBar`, `game.tl:417-455`). (b) is a hack.
- Tool-style windows (they take part in the tool stack and close with Esc and other tools): `tool_react_util.registerToolWithWindow(toolName, windowId, windowRecipe)` returns a `ReactToolDefinition` (`main/tool_react_util.d.tl:24-29`). Then call `getDefaultToolStackApi().push(tool, key, param, allowStacking)` (`builtin.d.tl:1242-1249`). Statistics is the reference implementation: `statistics/statistics.tl:668-701`.
- Recommended pattern: a mod `ModEntryPoint` plugin that copies `statistics.StatisticsEntryPoint` (`statistics/statistics.tl:670-701`). It does `react.onEvent("myModOpenDashboard", ...)` and pushes the tool or adds the window. Launchers anywhere then just call `react.fireEvent(nil, "myModOpenDashboard", param)`.

### 3.2 Buttons and launchers

- **Mod button strip:** a `::MainModButtonAreaExtension` plugin returning `builtin.Button{...}`. It is placed in the layer ridge (`main/game.tl:529-556`) and is gamepad-reachable through the auto "Mods" radial entry.
- **Game bar:** a `::GameBarInfoDisplayExtension` plugin. Clickable status chips are allowed (any recipe).
- **Radial menu:** a `::RadialMenuExtension` plugin returning `builtin.RadialMenuChild{icon, getInfoText, onActivate}` (pattern in `game_bar/game_bar.tl:171-180`).
- Adding buttons to the main game-bar menu itself (Lines, Vehicles, Statistics, ...) needs a replacement of `game_bar.GameBar` (exported, `game_bar/game_bar.tl`), which is high-conflict.
- **Public react events** a mod can fire, with `react.fireEvent(nil, name, param)` in recipes or `api.gui.fireReactEvent(name, param)` from game-script GUI code (`apidef/api/gui.d.tl:49`):
  - `selectEntity {entity, stack, dontBlink}` (`entity_window/view_manager.tl:617`), `selectViewKey`, `closeAllWindows`;
  - `openStatisticsWindow <TabKey "Line"|"Vehicle"|"Station"|"Warehouse"|"Depot"|"Town"|"Industry">` (`statistics/statistics.tl:691`), `closeStatisticsWindow`;
  - `openVehicleManager {openWithLineEntity, openWithVehicleEntities, openWithDepotEntity, sendToLineMode}` (`line_vehicle_mgmt/manager_window.tl:8447`), `closeVehicleManager`;
  - `buyVehicles`, `replaceVehicles`, `modifyVehicles` (`line_vehicle_mgmt/vehicle_store_window.tl:4870/4895/4932`), `duplicateVehicles` (`manager_window.tl:8494`);
  - `openFinanceWindow <TabKey>` (`main/game.tl:290`), `openCompanyWindow`, `openNotificationLog` (`game_mechanics/.../notifications/gui/notification_button.tl:27`), `openLayerRidge`, `openPauseMenu`;
  - `PushTool`/`PopTool` (`main/tool_react_util.tl:120/135`);
  - `setMenuFilter`, `setVehicleFilter`, `setDisableFeatures`, `setProtectedEntities` (`main/game.tl:148-166`).

  Full list: `grep -rn 'react.onEvent("' gui game_mechanics`.

### 3.3 Hotkeys and keybindings

- Input actions (IAs) are engine-defined. `app.getInputActionRep()` returns an `InputActionRep` with only `getAll()`/`get()` (`apidef/api/type.d.tl:3073-3099`, `apidef/app.d.tl:172`). There is no Lua `add`; `UI::InputActionRep::Add` exists only in C++.
- 162 `IA_*` ids are hard-coded in the exe (`SCR/ia_list.txt`). No content Lua file defines IAs. **A mod cannot add a new rebindable hotkey** (no evidence of a resource type for it).
- Options:
  1. `react.useInputAction("<existing IA>", react.iaHandler(fn, isEnabledFn))` inside a mounted recipe, for example the mod's ModEntryPoint. This is the same as the base statistics hotkeys (`statistics/statistics.tl:697-701`) and `game.tl:212-224`.
     - Conflicts and precedence with the base handlers of the same IA **need in-game verification**.
     - Candidate IAs that Lua does not use at all: the comm-diff in `SCR/ia_list.txt` vs `SCR/ia_used.txt`. Most are text/nav IAs, so there is no "free" IA.
     - `react.iaForward(ref, action)` forwards an IA to another component.
  2. The component meta `keyListener = function(evt) ... end` (e.g. `menu/settings_page.tl:246-260`; `evt.data:getKey()`, `api.gui.key.State`). It only fires while that component has focus; making it global **needs in-game verification**.
  3. Players can rebind existing IAs in Settings → key mapping (`keyCmdDefinitions`, `menu/settings_page.tl:131-213`, `1641-1665`). A mod cannot add entries there.
- For UX: plan for click/radial launchers. Hotkeys can only piggy-back on existing IAs, which is risky.

---

## 4. Data for overview dashboards (read from GUI code)

GUI recipes may read the engine directly. Example: the earnings plugin calls `api.engine.util.finance.calculateEarnings(api.engine.util.getPlayer())` every timer tick (`game_bar/game_bar_display_earnings_plugin/game_bar_display_earnings.script.tl:9-13`).

**Polling hooks** (`main/engine_react_util.d.tl:3-49`):
- `useStepStateTimer(getFromEngine, interval?, equals?)` is the dashboard workhorse;
- `useStepState(getFromEngine, makeCommand?)` returns `(state, commit)` and binds a value to a command;
- `useStepStateParallel` / `useStepStateParallelSimple(useFnName, params)` compute in a worker thread (`react.enqueueParallel`, `main/react.lua:56-65`);
- `react.onStepTimer(fn, sec)` defaults to 0.5 s (`main/react.lua:525-534`).

**Engine API** (`apidef/api/engine.d.tl`, `engine/system.d.tl`, `engine/util.d.tl`):
- Generic: `api.engine.getComponent(e, api.type.ComponentType.X)`, `getEntitiesWithComponent(type, filters?)`, `forEachEntityWithComponent`, `entityExists` (`engine.d.tl:1690-1723`). Also `api.engine.util.getPlayer()`, `getWorld()`.
- **Lines** (`api.engine.system.lineSystem`, `engine/system.d.tl:11-56`):
  - `getLines`, `getLinesForPlayer(player)`, `getLinesForStationGroup`, `getLineStops`;
  - `getProblemLines(player) -> {{line, LineProblem}}`, `getStationGroup2LineStopsMap`.
- **Line util** (`api.engine.util.line`, `engine/util.d.tl:142-258`):
  - `getLinesIssues(player, all) -> {line : {LineIssue}}`, `getLineIssues`;
  - `getLineProblems()`, `getDetailedLineProblems(line)`, `getLineStationProblems()`;
  - `getLineCapacityUsages(line, all)`, `calcLineStationThroughput`, `getMaxFrequency`, `getNoRoadConnectionProblems`.
- **Vehicles** (`api.engine.system.transportVehicleSystem`, `engine/system.d.tl:349-400`):
  - `getLineVehicles(line)`, `getLine2VehicleMap()`, `getDepotVehicles`;
  - `getNoPathVehicles()`, `getVehiclesWithState(state)`, `getLineCargoInfo`.
- **Vehicle util** (`api.engine.util.vehicle`, `engine/util.d.tl:424-520`):
  - `getVehicles()`, `getRunningCost`, `getDepreciatedValue`, `getVehicleMaintenanceState`;
  - `findBestDepotForLine`, `findBestLineAndDepotForVehicle`.
  - Components: `TRANSPORT_VEHICLE` (`state`, `userStopped`, `transportVehicleConfig`), `LINE`.
- **Stations and towns:** `api.engine.util.station.calculateStationUsage`, `calculateStationGroupCargo`; `api.engine.util.town.getTownProblems()`, `getTownCapacityUsage`, `getTownReachability`.
- **Finance** (`api.engine.util.finance`, `engine/util.d.tl:830-876`): `calculateEarnings(player)`, `calculateBalance(entities, t0, t1, ...)`, `computeFinanceTable(player, cfg)`, `getAccountChart`, `getPlayersBalance`, `calcIncomeSince`.
- **Logbook/charts** (`api.engine.util.logbook`): `getLogValuePerYear(entity, logName)`, `getChart(...)`. Also `api.engine.util.headquarters.getTransportedData()` and `api.engine.util.industry.getClosingIndustries()` / `getIndustryProductivityInfo`.
- **Notifications (problems):**
  - `gameCtx.accessNotificationCacheFn(entity) -> {Notification}` (`main/game_context.d.tl:64`, created in `main/game.tl:127`);
  - `game_mechanics/notifications/notification_util.tl` (types are `"notification"` generic resources, 27 base types; a mod can add its own).
- **GUI-side state:** `api.gui.game.getGuiSaveData(modId)` / `setGuiSaveData(modId, table)` persist per-mod GUI data in the savegame (`apidef/api/gui.d.tl:776-781`). The base uses `getGuiSaveData("")` for `hudFilter` (`hud/happy_change_display.script.tl:79`). Dashboard settings and pins go here.
- **UI introspection:** `api.gui.byId.isVisible(Recursive)`, `setVisible`, `setHighlighted`, `setEnabled` (`apidef/api/gui.d.tl:379-424`); `api.gui.contextHelper.collectSubjectStates(ids)`, `getIdsOfActiveTool()`.
- **Camera:** `focusEntity`, `focusPosition`, `followEntity` (`apidef/api/gui.d.tl:426-506`), for "jump to problem".

**Reusable base GUI modules** (`require "::/gui/<path>.tl"`; types in the matching `.d.tl`):
- `line_vehicle_mgmt/line_util.tl`:
  - `getLineCarriers`, `calculateFrequencySeconds`, `getLineHasVehicles`;
  - `sendVehiclesToDepot`, `sendVehiclesToLine`, `sellVehicle`, `getBestDepotForLine`;
  - `makeLineName`, `makeLineColor`, `filterLine`, `highlightLine` / `highlightStop`, ... (`line_util.d.tl`).
- `line_vehicle_mgmt/line_react_util.tl`: ready widgets `LineBalance`, `LineTransported`, `LineCargoDisplay`, `ColorWidget`, `LocateButton`, `ManagerNotificationWidget`.
- `line_vehicle_mgmt/vehicle_util.tl`: `getAge`, `getLifespan`, `getConditionText`/`Icon`, `getAvgMaintenanceState`, `getVehicleTypeFromEntity`.
- `line_vehicle_mgmt/vehicle_react_util.tl`: `VehicleWidget`, `VehicleBalance`, `ConditionIcon`, `HandleVehicleChanges`, `onBuy`, `getLineAndDepot`.
- `line_vehicle_mgmt/vehicle_list_react_util.tl`: `VehicleList`.
- `main/cargo_util.tl`: cargo names, icons, colours; `calculateSortedLineCargoInfo`, `calculateVehicleCargoFill`, `getInputOutputStocksForStation`, ...
- `main/industry_util.tl`: `getIndustryProductionData`, `isIndustryConnected`, `calcAnnualShipment`, ...
- `statistics/statistics_react_util.tl`: `ProblemsCell`, `getProblemsCompareValue`, `compareProblemsLess`, `createSearchField`, `createCarrierCategoryFilter`, `calculateCargoColumnDataForLine`/`Vehicle`.
- `entity_window/entity_window_util.tl`: `VehicleTable`, `ActionButtonBar`, `SendCommandButton`, `NotificationWidget`, `RatingBar`, `MaintenanceBar`, `getEntityLog`, ...
- `main/gui_react_util.tl`: `IconLabelIndicator`, `FocusTextInputField`, `makeHorizontalBox`/`makeVerticalBox`, `usePlugins`.
- Also `main/engine_react_util.tl`, `main/tool_react_util.tl`, `main/button_react_util.tl`, `main/popover_react_util.tl`, `main/color_util.tl`, `scripts/util.tl` (`formatTimePoint`), `scripts/table_util.tl`.

These are internal modules with **no stability guarantee**; signatures may change between builds.

---

## 5. Triggering game actions from the GUI

- `api.cmd.sendCommand(cmd, callback?(data, success, resultEntities), progress?)` (`apidef/api/cmd.d.tl:590-600`). In GUI recipes, **callbacks work** (`main/game.tl:671-680`, `entity_window/vehicle/vehicle.tl:340-350`). Callbacks are refused only in game-script `update()` (skill testing.md).
- Commands relevant to UX actions (`apidef/api/cmd.d.tl`, line numbers):

  | Action | Command |
  |---|---|
  | Buy vehicle | `makeVehicleBuyCmd(player, depot, TransportVehicleConfig)` :892 (+ assign: `vehicle_react_util.tl:340-360` chains `makeVehicleSetLineCmd` in the callback) |
  | Assign vehicle to line | `makeVehicleSetLineCmd(vehicle, line, stopIndex)` :922 |
  | Send to depot (optionally sell on arrival) | `makeVehicleSendToDepotCmd(vehicle, sellOnArrival, depot?)` :915 |
  | Sell | `makeVehicleSellCmd({vehicles})` :908 |
  | Replace/upgrade | `makeVehicleReplaceCmd(vehicle, tvc)` :898 |
  | Start/stop | `makeVehicleSetStoppedByUserCmd(vehicle, stopped)` :936 |
  | Manual departure, try depart, reverse | `makeVehicleSetManualDepartureCmd` :930, `makeVehicleTryToDepartCmd` :950, `makeVehicleReverseCmd` :903 |
  | Vehicle modifiers | `makeVehicleSetModifiersCmd` :942 |
  | Lines | `makeLineCreateCmd(name, color, player, Line)` :767, `makeLineUpdateCmd(line, Line)` :778, `makeLineDestroyCmd` :772 |
  | Rename / recolour | `makeEntitySetNameCmd(entity, name)` :679, `makeEntitySetColorCmd(entity, color)` :662 |
  | Game speed | `makeGameSetSpeedCmd` :708 |
  | Stocks / industries | `makeStockListDiscardCargoCmd`, `makeStockListSetModifiersCmd`, `makeIndustrySetManualDevelopmentCmd` |
  | Build/bulldoze | `makeWorldBuildProposalCmd` :961, `api.engine.util.proposal.createProposalRemove` |
  | GUI → own game script | `makeScriptingSendEventCmd(src, id, name, param)` :788 |

- Base helpers that already wrap these with protection and feedback logic:
  - `line_util.sendVehiclesToDepot` / `sendVehiclesToLine` / `sellVehicle`;
  - `vehicle_react_util.HandleVehicleChanges` / `onBuy`;
  - `entity_window_util.SendCommandButton`.
  - Respect `gameCtx.filters.protectedEntities` (`entity_window/vehicle/vehicle.tl:365`) and `disableFeatures`, as the base does, so campaign missions keep working.

---

## 6. Risks and what to verify first

**Compatibility with other mods**
- Plugins are additive. Several mods can plug into the same point; the only issue is ordering, so use a distinct `order`.
- Replacements are exclusive per recipe (§2.2). Two UX mods replacing `ManagerWindowContent` or `GameBar` conflict silently. Keep replacements few, small and wrapping.
- Campaign missions themselves replace `HudIconMasterGame` and `PerkHudIcon`. A UX mod must **not** replace those two, or the missions break.
- Recipe names are global for CSS (`R::Name`). Prefix all recipe names (e.g. `UxoLinePanel`). Event names are global too, so prefix custom events.
- Globals: `init.lua:233-252` logs an error for every global assignment in mods. Keep everything `local`.

**Savegames**
- A GUI-only mod (resources and scripts, no `*.gs.lua`) adds no game-script entity. Expect `severityAdd/Remove = "None"`, as in the official mods' `mod.json`.
- `setGuiSaveData(modId, ...)` writes data into the save. If the mod is removed, that data is presumably just ignored (**verify**).
- A `*.gs.lua` creates a GameScript entity in saves (skill engine.md §5).

**Game updates**
- The mod depends on internal module paths (`::/gui/...`), recipe exports, param records and event names, none of which are a public API.
- Pin to the build. Add a startup self-check that `require`s every used base module and asserts that the required fields exist; log a clear message instead of crashing. Re-run on every patch.

**Performance**
- Dashboards that scan all lines and vehicles every step are expensive. Use `useStepStateTimer` with ≥ 0.5–1 s or `useStepStateParallel`, and memoise per revision (`api.engine.getRevision`).

**Verify in-game first (smallest spikes)**
1. A staging mod with a `react-plugin ::GameBarInfoDisplayExtension` that returns a TextView: are mod `.res.lua` plugins discovered, and does the `.script.lua` module load?
2. A `react-plugin ::ModEntryPointExtension` that `debugPrint`s on mount and handles `react.onEvent("uxo.open")`. Fire the event from a `::MainModButtonAreaExtension` button and open a `builtin.Window` through `game_react_globals.getDefaultWindowApi().addSingletonWindow`.
3. A `react-replacement-config` that wraps an exported recipe, for example `line_react_util.LineBalance`, with `CallOriginalRecipe`: does it take effect, and does it combine with mission replacements?
4. Is a mod's `*.css.lua` applied automatically?
5. Does `react.useInputAction` with an existing IA in the ModEntryPoint fire, and which handler wins against base usages?
6. Is a `react-plugin ::StationGroupEowExtensionPoint` (no base plugins yet) rendered in the station window?
7. Optional: `addModifier("loadGameRes", ...)` and the `gui_res_overwrite` type, to re-order or hide base plugins without replacement.
8. Is there a dev hot-reload? The exe has `IA_DEBUG_RELOAD_REACT_COMPONENT` and "Reloading react root"; whether it is reachable outside debug builds is unknown.

---

## 7. Testing GUI mods with the template

Template: `/mnt/c/Users/maxbl/tf3-mod-template`. Its layout is `src/<mod>/content/<mod>/...`, it has an offline fengari mock (`spec/support/mock_engine.lua`) and an in-game driver `spec/ingame/run.sh`. The driver deploys the mod and the testbench to the staging area and launches `TransportFever3.exe --script <testbench>::/<dir>/app_script.lua`. The app script starts a 16x16 game with `MODS = {urbangames_no_costs_1, my_mod_1, my_mod_testbench_1}` (`spec/ingame/my_mod_testbench/content/my_mod_testbench/app_script.lua:11-36`). The testbench's game script prints `[testbench] PASS|FAIL ...` and `DONE`.

How to use it for GUI work:
- **Offline:** the mock has no react runtime. Put data shaping (line/vehicle aggregation, problem ranking, formatting) in pure modules that take plain tables, and spec those. Keep recipes thin. A minimal fake of `react`/`builtin` (functions that return tables) would allow snapshot tests of recipe output, but it is not in the template.
- **In-game, automated:**
  1. Add a `guiUpdate` step to `testbench.script.lua`; `guiUpdate` already runs on the GUI thread.
  2. From there: `api.gui.fireReactEvent("uxo.open", ...)` to open the mod's window, then on later frames `api.gui.byId.isVisibleRecursive("<meta id of your window>")` or `api.gui.contextHelper.collectSubjectStates({...})` to assert that it exists, and print PASS/FAIL.
  3. Give every mod component a `meta = { id = "uxo.dashboard" }`; the base does the same, e.g. `main/game.tl:381,421`.
  4. Recipes can `debugPrint` on mount, and run.sh greps `stdout.txt`.
  5. Exercise actions with real commands: build a line or depot in the scenario, then trigger the mod's button handler through an event and check components (e.g. `TRANSPORT_VEHICLE.state`).
  6. For visual checks: `api.gui.camera.takeScreenshot(scale)` writes to the userdata folder (`apidef/api/gui.d.tl:455`), or use the PowerShell screen grab described in skill testing.md (ask the user first).
- The `make validate` step (game validator) also applies to GUI mods, and `make content` must list all new `.res.lua`, `.script.lua` and `.css.lua` files in `_content.json`.

## Appendix: official mods and DLC scan

- Scanned:
  - `mods/release/urbangames_{campaign,campaign_mission_01..08,no_costs,sandbox,tycoon,vehicles_no_end_year}`;
  - `dlcs/urbangames_preorder_pack`.
- Their content is in UG-magic zips; the Lua/TL/JSON files are extracted to `SCR/modsx/`.
- GUI-related findings: only `react-replacement-config` in campaign missions 01 (`hud_replacement`) and 03, 05, 07 (`perk_icons_replacement`). No `react-plugin`, `gui_res_overwrite` or `.css.lua` files in mods. The missions also drive the UI through `api.gui.fireReactEvent("setMenuFilter" | "setDisableFeatures" | "clearToolStack" | ...)` from mission scripts (`mission_x/mission/mission_sim.script.tl:1220-1235`, `mission_x/mission/tasks/cutscene/cutscene.tl:38-51`).
- `mod.json` of the missions: `cosmetic:true`, `visible:false`, pre/postRun scripts. Nothing GUI-specific is required; resources are discovered by file type.
- Exe strings (react/plugin/keybind grep):
  - React is a C++ framework (`framework/ui/react/*.cpp`, `Game/scripting/react_interface.cpp`) with Lua states `Lua_React_Game` / `Lua_React_Menu`;
  - `_reactDoReplaceRecipes`, `gui_res_overwrite`, `.gres.lua`;
  - `UI::InputActionRep::{Add,SetKeyBindings,GetActionDesc}`, `keybinding_conflicts.cpp`, "Error while reading keybindings file";
  - `IA_DEBUG_RELOAD_REACT_COMPONENT`, "Reloading react root";
  - no `react-plugin` literal, because that string is built in Lua.
