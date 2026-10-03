# 02: Building and construction (gui/construction)

Scope: `SCR/game/gui/gui/construction/` (construction.tl 5087 lines, construction_react_util.tl 4105, construction_desc_react_util.tl 1059, menu/, tools/), plus the entry points that open it (game_bar.tl, entity_window_util.tl, view_manager.tl, con_availability notification, game.tl).
Paths below are relative to `SCR/game/gui/gui/` unless they start with `game_mechanics/` or `base/`.

Not in the extracted source: the base-game `.con`/`.module`/street/track resource files. Which station, depot or signal sits in which tab is set by each resource's `menuCategory`, so it cannot be fully checked here. Placements marked "(needs in-game verification)" are inferred from category names.

## 0. Architecture

The construction UI is one tool on the global ToolStack, `ConstructionTool` (construction.tl:5051-5085, `react.RegisterTool{name="Construction"}`). It owns one singleton window, `ConstructionListWindow` (construction.tl:4990-5035, id `menu.construction.react`, titled with the hard-coded, untranslated `"CONSTRUCTION ACTION"`). It also owns a second singleton, `ConstructionParamsWindow` (construction.tl:3070-3137, id `menu.construction.params.react`, title "Settings").

The list window holds an outer TabWidget with hidden indicators. Each tab is one top-level "menu" (category index 1..17, built in `initCategories`, construction.tl:3947-4257). Each menu holds an inner TabWidget of sublists (`ConstructionCategory`, construction.tl:2554-3028). Tab 1 is always a search field. Each sublist is a horizontal icon list (`ConstructionDefinitionsList`, construction.tl:514-888) with optional filter chips (`CategoryFilterPanel`).

Selecting an item builds a `ConstructionDefinition`. That definition is turned into an engine-native `builtin.ConstructionAction` by `construction_react_util.getActionParams` (construction_react_util.tl:3604-3983). The native action draws the preview and the cost/collision feedback, and applies the build.

Tool options are `ConstructionMenuParam`s. Params with `location == Toolbar` are drawn in a bottom bar (`ConstructionParamsContent` with `bottomBar=true`, construction.tl:4949-4963). All other params go to the "Settings" window.

## 1. Surfaces

### 1.1 Game-bar construction buttons (entry layer)
- Recipe: `ConstructionToolButton` (game_bar/game_bar.tl:604-655), grouped in `ConstructionToolButtonGroup`. Button data is at game_bar.tl:838-1000.
- Buttons, target tab and hotkey (input-action id):

| Group | Tooltip | toolVariant | tab index (+1) | Hotkey IA | Condition |
|---|---|---|---|---|---|
| Routes | Road | road | 1 | `selectRoad` | always |
| Routes | Rail | rail | 2 | `selectRail` | always |
| Routes | Water | water | 3 | `selectWater` | always |
| Routes | Air | air | 4 | `selectAir` | always |
| Infra | Roads | roads | 15 | `selectRoads` | always |
| Infra | Tracks | tracks | 17 | `selectTracks` | `hasTracksMenu` (not map editor, game.tl:452) |
| Infra | Warehouses | warehouse | 16 | `selectWarehouse` | `hasInfrastructures` |
| Perks/Land | Perks | perks | 14 | `selectPerks` | not map editor, not mission (game.tl:449) |
| Perks/Land | Landscaping | landscaping | 5 | `selectTerrain` | always |
| Builder | Town | town | 6 | none | `hasTownBuilder` |
| Builder | Industry | industry | 7 | none | `hasIndustryBuilder` |
| Bulldozer | Bulldozer | bulldozer | 8 | `selectBulldozer` | always |
| Bulldozer | Bulldozer (module) | module-bulldozer | 10 | `selectModuleBulldozer` | always (stacks on top) |

- Open/close: clicking the button calls `showFn`, which fires `constructionMenuSetTab {tabIndex, sublistId}` (game_bar.tl:615-618). That pushes `ConstructionTool` with `tabKey` (construction.tl:4859-4887). Clicking the active button again runs `hideFn`, which fires `closeConstructionWindow` (game_bar.tl:645-647, construction.tl:5003). Each button also listens to an `eventName` such as `openRail` or `openTracks`, which lets other code open a menu at a specific `sublistId` (game_bar.tl:620-626).
- Status shown: only the icon and a tooltip. A button is greyed out when its whole menu is empty (`constructionMenuCategoryEmpty`, game_bar.tl:608-613, fired at construction.tl:2699, 2741). There is no badge for new items, no count, no last-used state.
- Hotkey wiring: game.tl:837-848 forwards `select*` to the game bar. The default keys come from engine settings and are not in the source (needs in-game verification).

### 1.2 Construction list window, `ConstructionListWindow` / `ConstructionListContent`
- Recipe: construction.tl:4990-5035 (window), 4259-4988 (content). The window is `closable=true`, `movable=false`, `mouseTransparent=true`, `autoFocusOnBecomingVisible=true`.
- Layout (construction.tl:4935-4987): an invisible `ConstructionInfoPanel` that only drives callouts, then a FloatingLayout with the bottom-bar params at the bottom-left (`ConstructionParamsContent bottomBar=true`, id `menu.construction.bottomparams.react`) and the tab widget at the bottom-centre (`react.construction.menu.tabwidget`, `showIndicators=false`).
- Top-level menus (construction.tl:4036-4254; the index is significant because it is hard-coded elsewhere):

| idx | id | Kind | Sublists (menu_category res, order) |
|---|---|---|---|
| 1 | road | addCategoryNew ROAD | Search, Buildings (`road_buildings`,100), Tools (`road_tools`,1000), Assets (`road_assets`,8000) |
| 2 | rail | RAIL | Search, Buildings (`rail_buildings`,100) |
| 3 | water | WATER | Search, Buildings (100), Assets (200), Tools (1000) |
| 4 | air | AIR | Search, Buildings (100), Assets (300), Tools (1000) |
| 5 | landscaping | LANDSCAPING | Search, Terrain (100), Vegetation (1000), Ground (5000), Animals (6000), People (8000), Vehicles (10000), Residential/Commercial/Industrial/Other Town Buildings (14000-17000), Assets (20000) |
| 6 | town | TOWN | Search, Tools (`town_tools`: Town Builder 1000, Experimental Town Builder 2000) |
| 7 | industry | INDUSTRY | Search, Industries (100), Assets (3000) |
| 8 | bulldozer | single | Bulldozer (only param: Underground) construction.tl:4049-4082 |
| 9 | modules | MODULES (dynamic) | Search, Plots (0), Warehouse (0), Decoration (3), Platforms (2000), Building (3000), Landing / Road Access / Tracks (4000), Misc (5000) |
| 10 | module-bulldozer | single | `deactivateToTab=9` construction.tl:4231-4241 |
| 11-13 | heightmap / generate / generateStreets | deprecated empty ("removing causes redscreens", construction.tl:4243-4246) |
| 14 | perks | PERKS | Search, Landmarks (100), Prospecting (1000, 13 exploration types), Mechanics (10000: Marketing Campaign 1000, Industry Greenification 2000) |
| 15 | roads | ROADS | Search, [street-type categories defined in base res, e.g. `roads_highway` referenced in con_availability.script.tl; needs in-game verification], Road Constructions (5000), Tools (`roads_tools` 10000: Tram Track 100, Bus Lane 200, Crosswalk 300, Locking 1000, Traffic Light 1100, Crossing/Lane 1200) |
| 16 | warehouse | WAREHOUSE | Search, Warehouses (1000) |
| 17 | tracks | TRACKS | Search, Tracks (1000), Tools (10000: Electrification 5000 + edge decorations), Signals (13000), Rail Constructions (16000), Assets (19000) |

  The categories come from `menu/menu_categories/*.res.lua` (`type="menu_category"`). Items are assigned by each resource's `menuCategory.categories[{category, order, filterCategories}]` (construction_react_util.tl:3999-4069). A sublist whose only item is an "eraser" is dropped (construction.tl:4020-4022). Empty non-dynamic sublists are skipped (construction.tl:2593-2595).
- Item order: items are sorted by `order`, then by name (construction_react_util.tl:4032-4037). The track list is sorted by speed ascending (construction_react_util.tl:2451-2459). The street list puts town roads before country roads, two-way before one-way, and fewer lanes first (construction_react_util.tl:2015-2069).
- Status shown: icons only, with no text labels (`ConstructionDefinitionItem`, construction.tl:262-482). An item is greyed when disabled (rank lock, cooldown, max modules). A cooldown progress bar overlays the icon (construction.tl:369-377), and a "remaining" count appears for landmarks, HQ, perks and modules with rank permits (construction.tl:384-395). An icon can change by era (`ConstructionDefinitionMultiIcon`, construction.tl:218-239). Name, cost and the reason an item is disabled only appear in the hover callout (1.5).
- Actions: clicking an item selects it and activates the tool (`onSelect`, construction.tl:844-865). Hovering opens the info callout after 0.5 s (construction.tl:866-869, 3923). Each sublist has a fake close button (construction.tl:2514-2524). `IA_MENU_BACK` quits (construction.tl:2556). `IA_TOGGLE_LAYER_BUTTON_RIDGE` opens the layer ridge (construction.tl:4274-4276).
- Auto-select: when a sublist opens, the first enabled item is selected and the tool is armed immediately (construction.tl:613-618). Opening Tracks therefore arms the slowest available track.
- Refresh cadence: the disable cache (rank, permits, cooldown) refreshes every 1.0 s and on `onProposalApply` (construction.tl:4307-4315). List filtering runs on every step when the menu is `dynamic` (modules) or when search, year or filter changes (construction.tl:706-745). Category emptiness is checked on `heartbeat` (construction.tl:2707-2794).
- Code facts: there are no `ExtensionPoint` or `usePlugins` calls in the folder. Only `ConstructionListWindow` is exported (construction.tl:5087). Every inner recipe (`ConstructionCategory`, `ConstructionDefinitionItem`, `ConstructionParam`, `ConstructionInfoPanelCallout`...) is a file-local, so `ReplaceRecipe` cannot reach it. Data extension points:
  - `menu_category` resources (new tabs)
  - `menu_filter_category` resources (new filter chips)
  - `construction_tool` resources with `getDefinitionFn` / `isDisabledFn` (new tools in any tab; construction_react_util.tl:2813-2838)
  - the `setMenuFilter` React event (enabledItems/disabledItems/disabledParams allow and deny lists, game.tl:148-151, used by missions at mission_sim.script.tl:1220)

### 1.3 Per-menu sublist tab bar and search, `ConstructionCategory` / `ConstructionMenuSearch`
- Recipe: construction.tl:2554-3028 and 2209-2280. The inner `TabWidget` has tag `react.construction.menu.innerTabWidget`; its indicators are the category icons with the name as tooltip (`ConstructionMenuIndicator`, construction.tl:2174-2195).
- Search tab (always tab 1, `makeSearchTab`, construction.tl:3995-4002): a `TextInputField` with "Search...". It matches a case-insensitive substring of the name or description across all sublists of the current menu only (construction.tl:3974-3993, 587). It shows "No matches found" when empty (construction.tl:878-885). When search editing stops with no text or no results, the UI jumps back to tab 2 (construction.tl:2880-2903, 2977-2983).
  - Bug: `string.find` runs without `plain=true` (construction.tl:587). Lua pattern characters (`%`, `(`, `[`, `-`) in the query either match unexpectedly or raise "malformed pattern" (needs in-game verification).
- No global search, no favourites, no recently-used list. A grep for favourite/recent/history in construction/, game_bar/ and menu_category_util.tl returns nothing.

### 1.4 Filter chips, `CategoryFilterPanel` (main/menu_category_util.tl:45-90)
- Shown above a sublist when its items carry more than one filter category, excluding the case "All plus one" (construction.tl:2391-2424, menu_category_util.tl:55-57).
- Toggle buttons are icon-only (tooltip = name). The 85 filter categories live in `menu/filter_categories`: gauges (600mm..1500mm, 3rd_rail, cogwheel), catenary, high_speed, passenger/cargo, station/depot/stop, bridge/tunnel types, tree/rock/flower...
- Multi-select uses OR semantics. An empty selection means "*". Selection is component state inside the mounted sublist: it persists while the window lives but is never saved.
- Gamepad: `IA_OPTION2` focuses the chips (construction.tl:2414-2423).

### 1.5 Info callout, `ConstructionInfoPanel` / `ConstructionInfoPanelCallout`
- Recipe: construction.tl:3568-3932 (driver; renders nothing itself, uses `calloutContainerRef`) and 3523-3566 (content).
- Opens: on hover (0.5 s delay; no delay on repeat in mouse mode), on select, or when a Default-location param changes (`constructionOpenCalloutFromParams`, which auto-closes after 2 s, construction.tl:3845-3849). Closes: 0.3 s grace after hover leaves (construction.tl:3569, 3901-3909), on select (`closeOnceRef`), and on `onProposalApply` (construction.tl:3862-3864).
- Content:
  - title
  - preview image with attribute bubbles placed TopLeft/TopRight/BottomLeft/BottomRight: noise, pollution, speed limit, capacity, comfort, cargo types currently produced, cargo specialisation, climate zones, "(Unload Only)"
  - description
  - below the image: Cost (coin icon; `Free` / `X` / `Up to X` / `X to Y`, per km for tracks and roads) and Maintenance (`X/Year`), from construction_desc_react_util.tl:368-423
  - effects, permits ("Uses: n", "Unique Use", "Cooldown: …"), and the disabled reason as a warning bubble (construction.tl:3315-3323)
- Cost computation: for parametric constructions, `api.engine.util.construction.getConstructionResult(...)` runs on hover and is cached per param combination (construction.tl:3611-3677). Year-progression scaling is at 3596-3609. Module costs are scaled to the host construction's build year (construction.tl:3709-3718, 4342-4357).
- Status hidden: everything above sits behind a hover. The list icon shows no price, no lock reason and no name.

### 1.6 Bottom bar (tool options), `ConstructionParamsContent bottomBar=true`
- Recipe: construction.tl:1444-2167 and `ConstructionParam` 999-1213. Params are grouped (`group`) with separators (construction.tl:2024-2074). Each param's `checkEnabledFn` decides Enabled / Disabled / Hidden / InputActionOnly.
- Track builder params (`getTrackCategoryParams`, construction_react_util.tl:2186-2441):
  - Mode: Build Track / Replace Track (icon buttons)
  - Terrain Mode: Height Offset / Fixed Incline
  - Height slider (-5000..5000, cubic scale; resets on category change and on menu close)
  - Incline slider (only in Fixed Incline mode)
  - Bend slider (-1..1)
  - Follow Terrain checkbox (only with Height Offset and bend 0)
  - Snapping Yes/No (disabled while `IA_PRECISION_MODE` is held; resets on category change and menu close)
  - [experimental] Bridge Height / Tunnel Height (only if `appConfig.experimentalTunnelAndBridgeMinHeight`, construction_react_util.tl:1641-1716)
  - Underground Yes/No (kept across categories)
  - Bridge type, Tunnel type, Rail crossing type: icon buttons that open an `ObjectFilterBox` callout with its own filter chips (construction.tl:1179-1207, menu_category_util.tl:173-401). The default bridge or tunnel is auto-picked as the one whose speed limit is just above the track speed (construction_react_util.tl:305-350). The chosen type resets on category change.
- Road builder params (`getStreetCategoryParams`, construction_react_util.tl:1718-2005): Mode Straight / Curved / Replace Road; Terrain Mode; "Override Lanes" (only in Replace mode); Height; Incline; Bend; Follow Terrain; Snapping; Underground; Bridge, Tunnel and Crossing types.
- Electrification tool: Underground only (tools/rail_electrification_tool.script.tl). It is a separate tool; tracks themselves have no catenary toggle.
- Constructions (stations, depots, assets) via `makeConstructionBuilderParams` (construction_react_util.tl:851-928): Height (when `heightAdjustable`), Rotation (36 steps of 10°; X/Y rotation hidden), Random Rotation if the res defines it, the resource's own Toolbar params, and Underground.
- Brush tools (terrain, painter, assets; `getBrushConstructionParams`, construction_react_util.tl:2891-3143): Heightmap stamp, Single/Brush mode, Brush Size (32 steps), Strength (10%..100%), Height (single mode), Rotation, Incline Threshold, Random Rotation, Paint Steep, No Collision, Invert, Eraser Mode (InputActionOnly), Brush shape.
- Bus lane / tram tools: Symmetry (Single Lane / Symmetric), Catenary (year-dependent default), Underground. Crossing tool: Road / Tram lanes.
- Parallel or double tracks: no such parameter. `TrackEdgeBuilder` (scripts/builtin.d.tl:186-225) has no parallel or offset field, so this cannot be added from Lua. Whether double-track street templates exist needs in-game verification.
- Persistence: values are stored per menu index in a React ref (`refStoredParams`, construction.tl:1454, 1866-1899). `preserveValueInAllCategories` params (underground) share the value across menus. Values are never saved to disk; reloading the game resets them (inferred from ref-only storage). Reset flags are `resetOnCategoryChange`, `resetOnDefinitionChange` and `resetOnMenuClose` (construction.tl:1786-1864). The bulldozer is special-cased so it does not reset the previous menu (construction.tl:1839-1849).

### 1.7 "Settings" window, `ConstructionParamsWindow`
- Recipe: construction.tl:3070-3137 (`closable=false`, `movable=false`, `initialVisible=false`, class `construct-settings`).
- Visible only while the construction window is visible and the active definition has non-Toolbar params, or a module-builder entity has `postConstructionModifiable` params (construction.tl:1692-1702).
- Content: either the definition's Default-location params (for example station length or track count of non-modular .con constructions; res-dependent), or `ConstructionEntityParam` (construction.tl:1220-1442). In the second case every change is sent at once as `createProposalReplaceConstruction` + `makeWorldBuildProposalCmd` (construction.tl:1288-1317). There is no confirmation and no cost preview in this panel.
- Gamepad: `IA_TOGGLE_MOD_SETTINGS_CONSTRUCTION` toggles focus (construction.tl:1485-1487, 4405-4414). Key hints are drawn for 13 action source ids (construction.tl:3053-3068).

### 1.8 Module builder (station, warehouse and depot upgrades)
- Entry: in an entity window, the "Configure" wrench button calls `entity_window_util.makeConfigureOnClickFunction` (entity_window/entity_window_util.tl:1796-1808). It fires `setModuleBuilderEntity` and `constructionMenuSetTab{tabIndex=8+1 (MODULES), allowStacking=true}`. The button exists in the station group (station_group.tl:1044-1055, only if the construction is modifiable and owned), warehouse.tl:79-81, perk.tl:119-121, maintenance_station.tl:100-102, empty_construction.tl:47-49 and industry.tl:417.
- Dynamic list: module definitions are filtered by the entity's slot types (`api.engine.util.construction.getSlotTypes`). A type is disabled with "Maximum Number Reached" when `slotConfig.maxModules` is hit, and with "Maximum Number of Modules Reached" or a remaining count from rank permits (construction.tl:4090-4224). The list re-evaluates every step (`dynamic=true`).
- Layer: a "white screen" background contrast (optional via the Advanced setting `backgroundContrastMode`; construction_react_util.tl:488-499, settings_page.tl:~1195).
- Track modules are generated per track type in base/base/mod.script.tl:405-500 (`modules_tracks`, fixed price 30 000, maintenance 5 000).
- Module bulldozer: game-bar button / `selectModuleBulldozer`. It stacks (`allowStacking`) and its `deactivateToTab=9` returns to the Modules menu (construction.tl:2541-2550).
- Module costs are scaled by the station's build year (construction.tl:3709-3718).

### 1.9 Bulldozer
- Single-definition menu 8 (construction.tl:4049-4082). Its only param is "Underground" (Toolbar, kept across menus). HUD icon filter comes from `bulldozerHudIconFilter`.
- The engine-native `Bulldozer` action draws a circle border colour (construction_react_util.tl:3574-3583).
- No demolish button in any entity window. Grep for Bulldoze/Demolish/createProposalRemove in gui finds only the map editor and settings. Refund and cost display while bulldozing are engine-side (needs in-game verification).
- No undo anywhere: no "undo" in GUI code or in apidef (`api/cmd.d.tl`, `engine.d.tl`).

### 1.10 Engine-side placement feedback (native `ConstructionAction`)
- Preview, collision/validity colouring, the cost tooltip, snapping and slope feedback are rendered natively. The Lua side only supplies:
  - `ModifierColor` (valid/invalid/upgrade/downgrade/in-progress, construction_react_util.tl:35-45)
  - input-action prompts
  - `getProposalStringsFn`, which appends extra lines to the proposal tooltip. Today the only line is "Reputation: -x% (n towns impacted)" (construction_react_util.tl:3812-3864).
- Engine callbacks into the UI: `onHeightChangeFn`, `onFixSlopeToggledFn`, `onClearFn` (reset bend), `onFollowTerrainEnabledFn`, `onRotationChangeFn` (construction_react_util.tl:3753-3811). `streetBuilderRequestUnderground` switches the underground toggle (construction_react_util.tl:3894-3903).
- Custom selector actions (prospecting, marketing, greenify) use `SimpleTooltipRecipe`. It shows "Cost: X" in red when X exceeds the balance (construction_react_util.tl:1208-1254). For normal building, the exact error and cost texts are engine-side (needs in-game verification).

### 1.11 HUD icons during construction
- `ConstructionMenuHudIconMaster` (constructionHudIconMaster.tl) is configured per definition through `hudIcons`:
  - track builder: industry, town, signals, stations, depots, warehouses (construction_desc_react_util.tl:991-1005)
  - street builder: base nodes etc. (975-989)
  - depot/electrification: stations, depots, signals and a maintenance-station custom icon (1017-1032)
  - stations: station, town and industry, plus signals and warehouses (1041-1059)
- The layer config adds terrain contours for terrain and edge builders (construction_react_util.tl:554-576) and town Voronoi/district painting for town-related items (590-633). A preferred layer from the layer ridge overrides it completely (`mergeLayerConfig`, 3985-3990).

### 1.12 Jump to a construction from a notification
- "New Construction(s) Available" notification: `onClick` fires `constructionMenuSelectTabForConstruction{resName}` (game_mechanics/notifications/types/con_availability.script.tl:31-37). That handler finds the menu and sublist containing the resName (construction.tl:4889-4932) and opens it. It does not select the item itself; auto-select picks the first enabled item of that sublist.

### 1.13 Hotkeys inside tools (construction_react_util.tl:3604-3962)
Default key assignments are engine settings and not in the source (needs in-game verification).

| Input action | Effect | Applies to |
|---|---|---|
| `constructRaise` / `constructLower` | height +/- (or incline in Fixed-Incline mode; brush size; single-asset height) | constructions, roads/tracks, brushes |
| `constructOpt1` / `constructOpt2` | rotation +/- (constructions, brushes); bend +/- for roads/tracks | |
| `constructOpt5` / `constructOpt6` | brush strength; or a param keyed `constructOpt56` | |
| `constructOpt7` / `constructOpt8` | a param keyed `constructOpt78` | constructions |
| `IA_CHANGE_BUILD_MODE` | cycle mode: Straight/Curved/Replace road; Build/Replace track; Single/Brush | |
| `constructNoSnap` | toggle snapping | roads/tracks |
| `constructAlignToTerrain` | toggle Follow Terrain (only Height-Offset mode with bend 0) | roads/tracks |
| `IA_UNDERGOUND_MODE_TOGGLE` (sic) | underground view | all edge tools, bulldozer, constructions |
| `IA_PRECISION_MODE` (modifier) | fine steps; disables snapping; per-segment rebuild (TIP_CONSTRUCTION_7) | |
| `IA_TOGGLE_LAYER_BUTTON_RIDGE_CONSTRUCTION` | open layers | |
| `IA_OPTION2`, `IA_TOGGLE_MOD_SETTINGS_CONSTRUCTION` | focus bottom bar / Settings (gamepad) | |
| `IA_MENU_BACK` | quit menu (mouse); abort custom action (gamepad) | |

There are no hotkeys for: picking the next or previous item in a sublist, switching sublist tab, choosing bridge or tunnel type, toggling catenary, opening Configure on the hovered station, or the Town and Industry menus.

## 2. Task flows

Counting rules: C = clicks or key presses, S = distinct panels or windows visited, X = context switches (top-level menu change, or a jump between the map and an entity window). Map drags and placement clicks are counted separately as P. Hotkey paths are listed where they exist.

### 2.1 Build a rail line between two towns, with stations
1. Rail button / `selectRail` (1 C). The Buildings sublist opens and auto-arms the first station (construction.tl:613-618).
2. Narrow with filter chips if needed (passenger/cargo; 0-2 C). Pick the station icon (1 C). Hover 0.5 s to see the cost.
3. Optionally open the Settings window to set parametric options (length/tracks; res-dependent, 0-n C). Rotate with `constructOpt1/2` (n key presses).
4. Place station A (1 P). Pan the camera to town B and place station B (1 P).
5. Tracks button / `selectTracks` (1 C, 1 X). The Tracks sublist auto-arms the slowest track (sort ascending by speed, construction_react_util.tl:2451). The player usually has to pick a faster one (1 C).
6. Optionally pick bridge and tunnel types: open the callout, optionally filter, pick (2-4 C each).
7. Drag the track between the stations: one click per segment start and end (2 P per segment, usually many segments). Adjust bend and height with keys.
8. Optionally, for more than one train: Signals tab (1 C), pick a signal (1 C), click positions (n P).
9. For a depot: Rail menu again (1 C, 1 X), pick the depot (1-2 C), place it (1 P), back to Tracks (1 C, 1 X) to connect it (2 P).
10. Esc to close.

Total UI overhead without placement: about 10-16 C, 4 top-level menu switches (Rail, Tracks, Rail, Tracks), 2-4 callouts.
Alternatives: the Search tab inside a menu (type, then pick) instead of browsing tabs. The game-bar hotkeys remove the button travel.

### 2.2 Extend a station by 2 platforms
1. Click the station on the map (1 C). The station-group entity window opens (other area).
2. Click "Configure" (1 C, 1 X). The Modules menu opens. Which sublist opens first is the first non-empty one by order (Plots/Warehouse at 0, Decoration at 3), so it is often not Tracks or Platforms (needs in-game verification).
3. Tracks tab (1 C). Pick the track type (1 C; same speed-ascending order). Click 2 slots (2 P).
4. Platforms tab (1 C). Pick the platform (1 C). Click 2 slots (2 P).
5. Optionally the Road Access or Building tab for capacity (2+ C).
6. Esc.

Total: about 6 C, 4 P, 2 windows. A module that cannot be placed only shows its reason in the hover callout.

### 2.3 Upgrade a road (type, tram, bus lane)
- Type: Roads / `selectRoads` (1 C). Pick a street-type tab (1 C; tab names are res-defined). Pick the target road (1 C). Switch mode to "Replace Road" with the magic-wand icon (1 C) or `IA_CHANGE_BUILD_MODE` ×2 (Straight → Curved → Replace). Optionally Override Lanes (1 C). Drag over the road (P). About 4-5 C.
- Tram / bus lane: Roads (1 C), Tools tab (1 C), Tram Track Tool or Bus Lane Tool (1 C), optionally Catenary/Symmetry (1 C), drag. About 3-4 C.
- Pitfall: there are two "Tools" tabs in two different menus. ROAD → Tools (`road_tools`) is not the same as ROADS → Tools (`roads_tools`). The bus and tram tools only appear in ROADS; their `road_tools` entries are commented out (tools/bus_lane_tool.script.tl:35-38, tram_track_tool.script.tl:59-62).

### 2.4 Place a depot and buy a train
1. Rail (1 C), Buildings tab (auto), optionally the "depot" filter chip (1 C), pick the depot (1 C), rotate (keys), place (1 P).
2. Tracks (1 C, 1 X), pick a track (0-1 C), connect (2 P).
3. Esc (1 C). Click the depot on the map (1 C). Because the depot has no maintenance pool and has connected nodes, `view_manager.tl:557-567` opens the Vehicle Manager with `openWithDepotEntity` (other area). Buy there (≥2 C, other area).

Total: about 7 C plus purchase, 3 X.

### 2.5 Build a signal
Tracks / `selectTracks` (1 C), Signals tab (1 C), pick the signal type (1 C; Settings window if it has params such as one-way), click the track position (1 P per signal). About 3 C. Signals are `edgeObject` constructions built as `ACTION_STREET_TERMINAL_BUILDER` / `EdgeObjectBuilder` with `oneWay` taken from params (construction_react_util.tl:951-995, 3266-3276).

### 2.6 Electrify a track
- A (tool): Tracks (1 C), Tools tab (1 C), Electrification Tool (1 C), drag over the tracks (P). 3 C. Only available from `trackCatenaryYearFrom` onwards (rail_electrification_tool.script.tl:15-18).
- B (replace): Tracks (1 C), pick the catenary track type (1 C), "Replace Track" mode (1 C or `IA_CHANGE_BUILD_MODE`), drag. 3 C. This also changes the speed class.
- C (station tracks): inside the Modules menu, track modules carry `catenaryAdd`/`catenaryRemove` metadata (base/base/mod.script.tl:450-460). This path goes through Configure (2.2).

### 2.7 Demolish something
- Bulldozer / `selectBulldozer` (1 C), click or drag the object (1 P), Esc. 1-2 C. Underground objects need the Underground toggle (1 C or `IA_UNDERGOUND_MODE_TOGGLE`).
- A station module: Configure → Module Bulldozer (`selectModuleBulldozer` or button), click the module.
- No path from the entity window (no Demolish button) and no undo after a mistaken demolition.

### 2.8 Terraform or plant trees
Landscaping / `selectTerrain` (1 C), Terrain or Vegetation tab (1 C), tool (1 C), brush params (keys), paint (P). Each terrain change shows a reputation penalty in the proposal tooltip (construction_react_util.tl:3812-3864).

### 2.9 Use a perk (landmark, prospecting, marketing)
Perks / `selectPerks` (1 C), tab (1 C), item (1 C). Prospecting then needs a town click (custom selector, construction_react_util.tl:1449-1550). A locked or cooling-down item shows its reason only on hover.

### 2.10 Find an item whose menu you don't know
Open any menu (1 C). Search tab (1 C, or click the field). Type. The search only covers that one menu, so if the item lives elsewhere you repeat this per menu (up to 13 menus). A notification for a newly available item jumps to its sublist (1.12).

## 3. Friction findings

| # | Finding | Evidence | Impact |
|---|---|---|---|
| F1 | No undo for any construction or demolition, and no API to build one. | no "undo" in gui/ or apidef/ | High |
| F2 | Search is per menu, not global. Users must know which of ~13 menus holds an item (for example signals are under Tracks and depots under Rail; Roads and Road are separate menus). | construction.tl:3974-3993, 4010 | High |
| F3 | Rail work needs two top-level menus (RAIL = stations/depots, TRACKS = tracks/signals/electrification). Building a line means 3-4 menu switches. The same split exists for ROAD vs ROADS, each with its own "Tools" tab. | construction.tl:4036-4254; menu_categories/*.res.lua | High |
| F4 | Auto-select arms the first item, and tracks are sorted slowest-first, so the default track is usually wrong. There is no "remember last chosen item per sublist" across sessions, and none after a definition change when the sublist re-mounts. | construction.tl:613-618; construction_react_util.tl:2451-2459 | High |
| F5 | Icon-only lists: name, cost, maintenance, speed and the disabled reason are only in a hover callout with a 0.5 s delay. Lists cannot be compared without hovering each item one by one. | construction.tl:262-482, 3923 | High |
| F6 | No favourites or recently-used strip, and no pinning of items to the game bar. | grep: none | Med-High |
| F7 | No Demolish or Upgrade button on entity windows (station, depot, road). The user must leave the window, pick the bulldozer and find the object again. | entity windows have "Configure" only (entity_window_util.tl:1796-1808) | Med |
| F8 | Configure opens Modules at the first sublist by order (Plots/Warehouse/Decoration) instead of the most relevant one (Tracks/Platforms for rail stations). | construction.tl:2769-2779; modules_categories order values | Med |
| F9 | Bridge or tunnel choice resets on every category change and sits behind a callout button (2-4 clicks). The auto-pick by speed is invisible until you look. | construction_react_util.tl:1950-1964, 2384-2419, 305-350 | Med |
| F10 | Tool params are not persisted across save and load (React refs only). Snapping, height and bend reset on menu close or category change, so the user re-configures repeatedly. | construction.tl:1454, 1786-1864 | Med |
| F11 | No parallel or double-track option in the track builder; `TrackEdgeBuilder` has no field for it. | builtin.d.tl:186-225 | Med (engine) |
| F12 | Entity-param edits in the Settings window apply instantly, with no cost preview or confirmation (each change is a build proposal). | construction.tl:1288-1317 | Med |
| F13 | The Settings window is not movable and is separate from the bottom bar, so options for one tool are split across two places. Which panel a param lands in depends on `location`. | construction.tl:3116-3136, 1747 | Low-Med |
| F14 | Search uses Lua patterns (`string.find` without `plain`). Characters such as `(`, `%`, `-` misbehave and may raise errors. | construction.tl:587 | Low (bug) |
| F15 | Missing hotkeys: Town and Industry menus, next/prev item, sublist tab, bridge type, Configure-on-hover. | game_bar.tl:956-972 (no `iaForward`) | Low-Med |
| F16 | The window title is a hard-coded, untranslated "CONSTRUCTION ACTION". | construction.tl:5011 | Low |
| F17 | Magic tab indices (`8+1`, `tab=14/15/16`, `index ~= 9 and ~= 10`) and deprecated empty categories 11-13 that cannot be removed make adding or reordering menus fragile for mods. | entity_window_util.tl:1806; game_bar.tl:846-994; construction.tl:4243-4246, 4660 | Low (moddability) |
| F18 | The "Remaining" count and cooldown show only for perk, landmark and module items. There is no at-a-glance money check: the cost is not red when unaffordable, except in custom actions (`SimpleTooltipRecipe`). | construction.tl:384-395; construction_react_util.tl:1223-1235 | Med |
| F19 | The disabled reason appears only in the callout. A greyed icon gives no hint why (rank, cooldown, max modules). | construction.tl:339-343, 3315-3323 | Med |
| F20 | ObjectFilterBox filter bug: `updateSelection` passes the old state to `onFilterChange`, so the auto-switch to the first matching bridge or tunnel lags one click. | main/menu_category_util.tl:289 | Low (bug) |
| F21 | The module list rebuilds every step (`dynamic` forces `updateList` every frame) and the attribute cache calls `getConstructionResult` on hover. Possible stutter on large stations (needs in-game verification). | construction.tl:718, 3654 | Low |
| F22 | The notification "jump to construction" opens the sublist but does not select the item, so the user has to search for it again. | construction.tl:4889-4932 | Low |

## 4. Improvement opportunities

Moddability scale: Easy = data resources or existing events; Medium = `react-replacement-config` + `ReplaceRecipe` of an exported recipe, or monkey-patching a function on a shared module table; Hard = reimplementing the 5000-line `ConstructionListWindow`; Not feasible = needs an engine change.

On module tables: `ug_require` caches modules in `package.loaded`, because the loader returns a value (base/base/init.lua:80-90). Callers such as construction.tl:4437 call `construction_react_util.getActionParams(...)` through the table field at runtime, and `forEachDefinition` builds its function list at call time (construction_react_util.tl:2799-2807). A patch applied in a `react-replacement-config` `doReplaceFn` before init (gui/main/bootstrap_game.tl:12-50) should therefore take effect (needs in-game verification).

| # | Proposal | Saving | Moddability |
|---|---|---|---|
| I1 | Global construction search / command palette: one hotkey, type, Enter. It jumps to the item's menu and sublist and selects the item. | Find an unknown item: up to 13 menus × 2 C down to 1 hotkey + typing + 1 Enter | Easy-Medium. Opening the right menu and sublist already exists through the `constructionMenuSelectTabForConstruction{resName}` event (construction.tl:4889-4932). Item enumeration is available via `construction_react_util.forEachDefinition` / `getMenuCategories` (exported). The palette can live in a separate window or tool. Selecting the exact item afterwards needs one of: a patched `ConstructionDefinitionsList` (file-local, not replaceable, so Hard), or the "remember last item" mechanism of I3. A mod palette with its own matching would also avoid F14 (pattern search). |
| I2 | Favourites / recently-used bar: pinned items shown as a strip; one click arms the tool. | 2-3 C (menu → tab → item) down to 1 C | Medium. The strip can be a separate HUD window. Arming the tool goes through `constructionMenuSelectTabForConstruction` (1-2 C). True one-click selection needs patched selection logic (see I3). "Recently used" can be tracked by hooking `getActionParams` (monkey-patch) or by listening to `onProposalApply`. Persist with the game's settings or mod storage (needs verification). |
| I3 | Remember the last selected item per sublist (across sessions) and default to the newest or fastest track/road instead of the slowest. | Removes 1 C on almost every rail session (F4) | Medium. Re-sorting is easy: monkey-patch `construction_react_util.getTrackDefinitions` / `getStreetDefinitions` to sort descending by speed or year (construction_react_util.tl:2443-2507, 2007-2168). They are called via the table at call time (2799-2807). Remembering the selection needs `ConstructionDefinitionsList` (file-local), so Hard, unless only the order is changed: put the last-used item first through a patched `getMenuCategories` (exported, construction_react_util.tl:3999). |
| I4 | Merge RAIL + TRACKS (and ROAD + ROADS) into one "Rail" / "Road" menu: one menu with Stations, Depots, Tracks, Signals and Tools tabs. | Rail line build: 4 menu switches down to 0-1 | Easy. Pure data: ship replacement `menu_category` resources with the same `category` id but `menu="RAIL"` (for example `tracks`, `rail_signals`, `rail_tools` → `RAIL`), plus `construction_tool` getDefinition overrides. Mods can override vanilla res by path. The game-bar Tracks button would then open an empty menu and grey out automatically (constructionMenuCategoryEmpty). Verify override precedence in-game. |
| I5 | Info-dense list items: show price, maintenance and speed under each icon, and colour price red when unaffordable. | Removes N hovers when comparing N items; affordability at a glance | Hard. `ConstructionDefinitionItem` is file-local. The only route is to replace the whole exported `ConstructionListWindow`, which can be copied from construction.tl and modified (~5000 lines). An alternative is to shorten the callout delay or keep it pinned, which also needs the file-local `ConstructionInfoPanel`, so Hard. |
| I6 | Extra proposal tooltip lines: total cost vs balance, km built, max speed of the curve, "unaffordable" warning, terrain cost share. | Surfaces build status without a mental calculation | Medium. Monkey-patch `construction_react_util.getActionParams` to wrap `actionParams.constructionActionParams.getProposalStringsFn` (construction_react_util.tl:3812). That is the only Lua hook into the native placement tooltip. Which proposal fields are readable is in the `Proposal`/`ProposalData` types (needs verification). |
| I7 | "Demolish" and "Upgrade" buttons in entity windows (station, depot, road segment): one click removes, or arms the bulldozer focused on the entity. | Demolish from a window: 3+ C plus finding the object again, down to 1-2 C | Medium. Station and depot windows expose extension points (for example `EmptyConstructionEowExtensionPoint`, `usePlugins` in empty_construction.tl:34; station_group plugins are another area). Removal via `api.engine.util.proposal.createProposalRemove` (used in map_editor.tl:1614) + `api.cmd.makeWorldBuildProposalCmd`. Add a confirmation (no undo). |
| I8 | Configure opens the most relevant module tab (Tracks/Platforms for rail stations, Road Access for bus stations). | Station extension: -1 to 2 C | Easy. Fire `constructionMenuSetTab{tabIndex=9, sublistId="menu.construction.modules.modules_tracks"}` after Configure. Sublist ids follow the pattern `menu.construction.<menu>.<category>` (construction.tl:4027) and the handler supports `sublistId` (construction.tl:2809-2822). The Configure buttons themselves are in entity-window code; replacing `entity_window_util.makeConfigureOnClickFunction` on the shared module table is a monkey-patch (Medium). |
| I9 | Sticky bridge/tunnel/crossing choice and persisted tool options (snapping, follow terrain, underground, last track per menu). | Re-configuration after each menu switch: 2-4 C down to 0 | Medium-Hard. The reset flags live on the param records built in file-local `getTrackCategoryParams`/`getStreetCategoryParams`. They can be changed by wrapping the exported `getTrackDefinitions` / `getStreetDefinitions` and post-processing `definition.params[i].resetOnCategoryChange=false`. Persistence across save and load needs storage outside React refs (needs verification). |
| I10 | More hotkeys: next/prev item in the sublist, next/prev sublist tab, cycle bridge type, Town/Industry menus. | 1-2 C per change down to 1 key | Medium. Town/Industry: the game bar needs an `iaForward` (game_bar.tl:956-972, other area; custom input actions need engine registration, so needs verification). Item and tab cycling: file-local recipes, so Hard. Bridge cycling: a `stepValueFn` hook through patched params (I9) + `addStepValueInputActionHandlers` in `getActionParams` (patchable, Medium). |
| I11 | Hide obsolete or irrelevant items (expired eras, unused gauges, decorative assets) to shorten lists. | Shorter lists, fewer filter clicks | Easy. `setMenuFilter` event with `disabledItems` (definition tags `resName[@template]`, construction.tl:249-260) and `disabledParams` (param ids such as `streetBuilder.mode_street`). Caveat: missions use the same slot (mission_sim.script.tl:1220), so merge rather than overwrite. |
| I12 | Show the lock/disabled reason on the icon (small lock or rank badge, cooldown time). | Removes hover-to-learn-why | Hard (file-local `ConstructionDefinitionItem`). Partial workaround: `definition.disabled.message` is already shown, so a patched `getMenuCategories` could rename `name`, but icons stay unlabelled. |
| I13 | Fix search patterns and global search (F14). | Bug fix | Hard for in-place (file-local). Easy as part of I1. |
| I14 | Notification jump selects the item (F22). | -1 C | Hard in place (file-local list). With I3 last-used-first ordering, the new item can be made first in the patched `getMenuCategories`, so auto-select picks it (Medium). |
| I15 | Parallel / double-track builder. | Halves track drags for double lines | Not feasible in Lua (no field in `TrackEdgeBuilder`, builtin.d.tl:186-225). A partial alternative is a script tool that builds a second edge via proposals offset from the first (`api.engine.util.proposal`, needs verification). |
| I16 | Undo the last construction. | Large time saving on mistakes | Not feasible generally (no engine undo). A limited "undo last placed construction" could record the entity from `onProposalApply` and send a remove proposal; edges and terrain cannot be reverted. Needs verification. |
| I17 | A new tool in any tab (for example a "Station extender" preset or a combined "Electrify + upgrade speed" tool). | Task-specific shortcuts | Easy. Add a `type="construction_tool"` res with `getDefinitionFn` returning a `ConstructionDefinition` with `menuCategory`. A `customAction` recipe can use `RegisterCustomSelectorBasedActionRecipe` (exported, construction_react_util.tl:1282-1442) for click-on-entity tools. |

Moddability in short: data-level changes (menu regrouping, new tools, hiding items, opening a specific sublist through events) are easy. Changing list behaviour (selection memory, info under icons, keyboard navigation) means replacing the single exported `ConstructionListWindow`, because every inner recipe is file-local. The cleanest approach is a full fork of construction.tl registered through `react-replacement-config` → `ReplaceRecipe(ConstructionListWindow, forked)`.
