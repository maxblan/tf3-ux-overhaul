# 01c: Map layers, overlays and map HUD (in-game shell, sub-part)

Scope: `gui/layers/**`, `gui/hud/**`, `gui/main/hud_icon_toolbox.tl`, `hudIconMaster.d.tl`, `town_hud_react_util.tl`, `selector_react_util.tl` (where the default HUD lives), `callout_react_util.tl`, `callout_container.tl`, `game_tooltips.tl`, `particle_react_util.tl`, plus the notification HUD-icon pipeline (`game_mechanics/notifications/types/notification_react_util.tl`) because it decides which warnings show on the map.
Paths are relative to `SCR/game/gui/gui/` unless they start with `game_mechanics/`, which means `SCR/game/game_mechanics/game_mechanics/`.

The physical key for each `IA_*` input action is not in the Lua/Teal code. Input actions are only referenced by id (no keymap file in the extracted sources). Physical keys therefore need in-game verification (Settings → Controls).

## 1. Surfaces

### 1.1 Layers button and button ridge (`ExpandableLayerButton`)
- Name: `ExpandableLayerButton` (layers/layers_button_ridge.tl:304-608). Mounted in `game.tl:528-555` inside `game-button-ridge-area` at the top-left (FloatingLayoutChild h=0, v=0). `MainModButtonArea` (mod extension point) sits right next to it (game.tl:552).
- Purpose: a single toggle button ("Data Layers", icon `symbol_layers.tga`). When expanded, it shows a vertical ridge of 11 layer toggle buttons.
- Entry points:
  - Mouse: click the layers button. This only expands the ridge (layers_button_ridge.tl:541-550), so a second click on a layer is needed.
  - `IA_TOGGLE_LAYER_BUTTON_RIDGE`: forwarded as IA_SELECT to the layers button (layers_button_ridge.tl:475). Forwarded from the GameUIRoot (game.tl:216) and the outer root (game.tl:806).
  - Per-layer hotkeys `IA_TOGGLE_LAYER_TERRAIN|CIVILIZATION|INFRASTRUCTURE|TRAFFIC|PASSENGER_FLOW|PUBLIC_TRANSPORT|CARGO_FLOW|CARGO|NOISE|POLLUTION` (layers_button_ridge.tl:326-425, forwarded game.tl:217-226, 807-816).
    - Ridge collapsed: the hotkey expands the ridge and opens that layer (layers_button_ridge.tl:485-492).
    - Ridge expanded: the hotkey is forwarded to the ridge (481), and `switchTo` acts as a toggle. The same key closes the layer and collapses the ridge (175-184); a different key swaps the layer.
  - Event `openLayerRidge` with `{layer = <button id>, stack = true}` (447-462). It is fired by:
    - the radial menu (game_bar/game_bar.tl:87, gamepad)
    - the construction menu: `IA_TOGGLE_LAYER_BUTTON_RIDGE` in construction.tl:4274-4276 and `IA_TOGGLE_LAYER_BUTTON_RIDGE_CONSTRUCTION` in construction_react_util.tl:3656
    - town rating bars in the town window, via `onClickEvent` (game_mechanics/towns/town_util.tl:654, 665, 676, 690, 704 → traffic / satisfaction / cargo / noise / pollution layer)
    - the town-building window noise bar (entity_window/town_building/town_building.tl:186)
  - There is no hotkey for HUD Filters: no `inputActionId` (layers_button_ridge.tl:427-437).
- Closing:
  - click the layers button again
  - `IA_MENU_BACK` in the ridge (237-239)
  - the `closeLayerRidge` event or the `closeAllWindows` event (464-472)
  - leaving the construction menu (`constructionMenuActive` false → collapse, 505-512)
- Status shown: icon toggle state only. Each layer name is a hover tooltip (`tooltip = button.desc`, 265), with the hotkey shown as `tooltipModifierInputAction` (266). The ridge has no text labels.
- Actions: 11 `ToggleButton`s (260-282). Clicking an active one again closes it. Clicking another one pops the current `LayerTool` and opens the new one. Only one layer can be active (single `toggleButtonIndexState`, 173; `addSingletonWindow(LayerWindow)` 125/228).
- Modes: `StandaloneTool` pushes `LayerTool` on the tool stack (223). `ConstructionMenuAssist` is used while the construction menu is open and opens only the window, with no tool (224-229, mode chosen at 590). A KeybindingHintDisplay showing `IA_TOGGLE_LAYER_BUTTON_RIDGE_CONSTRUCTION` is drawn next to 11 construction action source ids (514-563).
- Enabled set: game.tl:539-551. All layers in game; only Terrain, Civilization and HUDFilter in the map editor. `DisableFeatures.Layers` (main/disable_features.d.tl:9) removes all buttons (layers_button_ridge.tl:311-316).
- Code facts:
  - Recipes: `ExpandableLayerButton` (exported), `ButtonRidge` (local, 172), `LayerWindow` (local wrapper of builtin.Window, id `menu.layers.window`, 32-83).
  - Tool: `LayerTool` = `tool_react_util.registerDelegatingTool{name="Layer"}` (120-152). Shelving (when another tool is pushed on top) hides the window and fires `layerToolShelved` (140-147).
  - Events: `openLayerRidge`, `closeLayerRidge`, `closeAllWindows`, `preferredLayerConfig`, `layerToolShelved`, `constructionMenuActive`.
  - No ExtensionPoint/usePlugins: the button list is hard-coded (316-438).

### 1.2 Layer window (common shell for each layer)
- `LayerWindow` (layers_button_ridge.tl:32-83): closable `builtin.Window` titled with the layer name. Closes via X, `IA_MENU_BACK` (33-35) or toggling the ridge button.
- Each layer content recipe:
  - fires `preferredLayerConfig` on mount (e.g. layer_terrain.tl:151)
  - registers an `ActionDescriptor` via `param.setActionFn` containing `LayerConfig` (the engine render config), `HudIconManagerConfig` (a layer-specific HUD), a `Selector` and an `ActionTooltip`
- In-window gamepad navigation: `IA_NAV_UP/DOWN` switch to the previous/next layer; `IA_TOGGLE_LAYER_BUTTON_RIDGE_CONSTRUCTION` → `reduce` (close layer, keep game) (e.g. layer_traffic.tl:401-403).
- `game.tl:129-133` stores the last `preferredLayerConfig` in `gameCtx.preferredLayerConfig`. Construction reuses it: `mergeLayerConfig` returns the layer config if set (construction_react_util.tl:3985-3987; construction.tl:4423). An active layer therefore stays visible while building.
- Persistence: none for the layer choice or the per-layer options. All option state is local `react.useState` and resets on every open (e.g. layer_cargo.tl:276-281, layer_infrastructure.tl:159-164, layer_passenger_flow.tl:162-168). Closing fires `preferredLayerConfig nil` (layers_button_ridge.tl:99, 135). Only HUD Filters persist (1.3.11).
- Clicking on the map inside a layer: `selector_react_util.makeDefaultSelector(..., allowStacking=true, ...)` (e.g. layer_traffic.tl:436). A click fires `selectEntity {stack=true}`, which `view_manager` handles by opening an entity window stacked on top (entity_window/view_manager.tl:617-626). Terrain uses its own Selector with the same behaviour (layer_terrain.tl:183-210).
- Hover inside a layer: `layer_react_util.makeFilteredSelectorTooltips` (layer_react_util.tl:327-335) shows `DefaultEntityToolTip` filtered to the layer's component prefilter.

### 1.3 The individual layers

The common pattern is in layer_react_util.tl:
- `GradientLegend`s with coarse labels such as "Low/High" or "Good/Bad" (131-171)
- `TownRatingHudIcon` (210-262): town name plus one 5-step rating bar
- `TownDemandsHudIcon` (264-325)
- `LayerLegendWrapper` / `LayerLegendFakeWindow` (337-361)

| # | Layer (button id / tag) | Hotkey | Map rendering (LayerConfig) | Legend / options in window | Layer HUD icons | File:line |
|---|---|---|---|---|---|---|
| 1 | Terrain (`menu.layers.terrainButton` / `menu.layers.terrain`) | IA_TOGGLE_LAYER_TERRAIN | Height colour map (thresholds 0/150/300/450), contour lines (metric/imperial), water and navigable water, flat colours for buildings, vehicles, industries and stations | Height gradient Low→High, contour-line legend with lengths, navigable-water swatch. No options | Default HUD (`HudIconMasterBase`) for station groups, signals, depots, towns, industries and warehouses | layer_terrain.tl:13-261 |
| 2 | Towns / Civilization (`menu.layers.townsButton` / `menu.layers.towns`) | IA_TOGGLE_LAYER_CIVILIZATION | Land-use colours (residential, commercial and industrial, 4 building levels), industries, town Voronoi areas | 4 discrete legends (Residential, Commercial, Industrial District, Industries). No options | Towns only (`HudIconManagerTowns`) | layer_civilization.tl:288-455 |
| 3 | Infrastructure (`menu.layers.speedButton` / `menu.layers.speed`) | IA_TOGGLE_LAYER_INFRASTRUCTURE | Speed-limit colours for the network (5 levels; underground and tunnels separate), signs, catchment areas with god-rays | Areas combo: None / Passengers (default) / Cargo / Vehicle Maintenance. Speed Limit combo: All (default) / Player Owned / Locked. Legend Slow→Fast | Station groups, depots, towns | layer_infrastructure.tl:23-264 |
| 4 | Traffic (`menu.layers.trafficButton` / `menu.layers.traffic`) | IA_TOGGLE_LAYER_TRAFFIC | Road traffic colours (Jammed / Intermediate / Fluid, 5 discrete levels) on network and vehicles | Legend "Traffic Flow" Good→Bad. No options | Vehicles: default icon. Towns: notification icons plus the `traffic_congestion` rating bar | layer_traffic.tl:297-458 |
| 5 | Passenger Flow (`menu.layers.mobilityButton` / `menu.layers.mobility`) | IA_TOGGLE_LAYER_PASSENGER_FLOW | Origin/destination building colours, public vs private transport flow on edges (5 levels), per town | Origin/Destination swatches, town combo (All Towns + alphabetical list), Public Transport checkbox (gamepad IA_OPTION2), Private Transport checkbox (IA_OPTION1), two legends | Passenger stations, passenger-capable vehicles, towns | layer_passenger_flow.tl:13-303 |
| 6 | Passenger Satisfaction (`menu.layers.publicTransportButton` / `menu.layers.public_transport`) | IA_TOGGLE_LAYER_PUBLIC_TRANSPORT | Station and terminal happiness colour (happy / aloof / sad), satisfaction edges (thresholds 1/10/25/50 %), town Voronoi | Legend "Happiness" Good→Bad. No options | Stations: waiting passengers plus a count of unhappy passengers with an emote (`createStationHud`, layer_public_transport.tl:355-378). Vehicles: passenger load. Towns: `people_happiness` rating bar plus notifications | layer_public_transport.tl:333-616 |
| 7 | Cargo Flow (`menu.layers.cargoFlowButton` / `menu.layers.cargo`) | IA_TOGGLE_LAYER_CARGO_FLOW | Town supply colours by district (5 levels), player cargo transport rate on edges. Passengers are always excluded (`getConfig(false)`, layer_cargo_flow.tl:309) | Legends: Cargo Transport Rate, Commercial, Industrial and (if any town needs it) Residential supply. No cargo filter | Town district demand/supply indicators (district sub-icons enabled via `resetSubEntityThresholds`, 321-325), industry and warehouse stock in/out, cargo stations, vehicles | layer_cargo_flow.tl:17-370 |
| 8 | Cargo Satisfaction / Delivery on time (`menu.layers.cargoButton` / `menu.layers.cargo_ontime`) | IA_TOGGLE_LAYER_CARGO | Warehouse happiness colour, satisfaction edges for the selected cargo types, Voronoi | Cargo Filter combo (All Cargo + currently produced types, alphabetical); legend "Delivery Time" | Vehicles carrying the selected non-passenger cargo (load), warehouses (stock), towns (`cargo_delivery` rating) | layer_cargo.tl:14-361 |
| 9 | Noise (`menu.layers.noiseButton` / `menu.layers.noise`) | IA_TOGGLE_LAYER_NOISE | Emission colour map (dB average), affected town buildings, emitter colouring of vehicles | Legends: Noise Emission, Affected Buildings ("Noise Absorption" is commented out, 123-141). Terrain tooltip mode "Noise" shows a 0..N level under the cursor | Vehicles (coloured by emission), towns (`noise` rating) | layer_noise.tl:15-237 |
| 10 | Pollution (`menu.layers.pollutionButton` / `menu.layers.pollution`) | IA_TOGGLE_LAYER_POLLUTION | As Noise, plus Voronoi, a wind renderable and a pollution catchment area | Legends: Pollution Emission, Pollution Absorption, "Affected Region" swatch. Tooltip mode "Pollution" | Vehicles, towns (`pollution` rating) | layer_pollution.tl (diff vs noise; tooltip mode at 219) |
| 11 | HUD Filters (`menu.layers.hudFilters` / `menu.layers.hud-filter`) | none | none (it uses `makeDefaultSelectorAction`, i.e. the normal game HUD, 231) | Icon toggle grid (see 1.3.11) | normal HUD | layer_hud_filter.tl:10-251 |

`layer_react_util.buildMouseEmissionInfo` (layer_react_util.tl:173-208) defines a "Mouse Position Info" checkbox with dB values, but no shipped layer uses it (debug-style helper).

#### 1.3.11 HUD Filters (only persistent display setting)
- Toggles are written to `api.gui.game.getGuiSaveData("").hudFilter` via `setGuiSaveData` (layer_hud_filter.tl:58-67, 79-82, 207-217). This data is per savegame (needs verification whether it is also global).
- Buildings row: Stations, Industries, Warehouses, Towns, Landmarks (`preFilters[componentType]`, 94-98).
- Vehicles row: Trains, Road vehicles, Trams, Ships, Aircraft (`preFilterTvCarriers`, 102-106). If all are hidden, `TRANSPORT_VEHICLE` is removed entirely (selector_react_util.tl:61-65).
- Miscellaneous row:
  - Costs and Income (floating money popups, engine-drawn via `showCosts` / `showIncome`, selector_react_util.tl:219-220)
  - Events (happy/sad emotes, greenification leaves, marketing megaphones; hud/*.script.tl)
  - Cargo Flow (ephemeral cargo icons flying between vehicle and stock; hud/cargo_flow.script.tl:147-158)
- Icons only; labels are hover tooltips. Gamepad: `IA_BACK` either switches to the previous layer or reduces (17-23).
- Read by `makePreFilter` (selector_react_util.tl:43-86) for the default HUD and by the hud game scripts (`showEventIcons`, `showCargoFlow`).

### 1.4 Default map HUD (no layer active): `HudIconMasterGame`
- Configured by `selector_react_util.makeDefaultSelectorCombinedFn` (selector_react_util.tl:194-241; inspector/default action) and `makeDefaultSelectorAction` (324-365, used by tools and windows). Both use `HudIconManagerConfig{ masterRecipe = hud_icon_toolbox.HudIconMasterGame, preFilter = makePreFilter(...) }`.
- Default component prefilter (selector_react_util.tl:14-24): TRANSPORT_VEHICLE, INDUSTRY, WAREHOUSE, STATION_GROUP, TOWN, BASE_NODE, SUBCONSTRUCTION. STOCK_LIST is commented out.
- Visibility (hud/hud_react_util.tl:53-153):
  - camera height threshold 150, lower cutoff 30, far-LOD range 3000
  - per component: render-distance scale, layer and physicsImpact. LINE is `forceVisible`; TOWN has `minDist` 250; TOWN_BUILDING has `maxDist` 3000
  - sub-entities: station terminal details below 350 m; town districts never by default (`detailsThreshold = -1`, 146)
  - scale factors in `hud/hud_gui_config.gres.lua:5-14` (all 1.0) are a data file that can be modded
- What is visible at a glance (`HudIconMasterGame`, hud_icon_toolbox.tl:160-370; refreshed by `useStepStateTimer`):
  - Vehicles: "stopped by player" icon, "returning to depot" icon (291-311), cargo load info with loading indicator (`makeVehicleCargoInfo`, 312-320), and the default icon when empty (unless `hideEmptyVehicles`).
  - Industries / warehouses / stock lists (player-owned or unowned only; town buildings excluded "as very cluttered", 201-209), via `StockHudIcon` (55-110):
    - output stock count per cargo
    - storage stock count, coloured Normal/Inferior/Poor by spoiled share (64-68)
  - Stations (station group): waiting passenger count, coloured Inferior if any passenger is unhappy and Poor if more than half are (112-143, 212-240). Cargo waiting at stations is not shown in this code path (passenger-only `getCargoQualityDataAtStationGroup(..., passengerCargoTypeId)`, 234). Needs in-game verification whether the engine adds another cargo indicator. The terminal number label is shown only for the selected entity (335).
  - Towns (`TownHudIcon`, main/town_hud_react_util.tl:46-191): capital crown, name, population, growth-arrow icon (Mediocre/Good → high, VeryGood/Excellent → very high), growth progress bar, icons of cargo types the town receives.
  - Dead-end path nodes (BASE_NODE): default icon (347-350).
  - Construction-specific custom HUD: `desc.hudIconScript` (243-252, 353-356). Example: pollution_cleanup_facility.con.lua:128.
  - Notification icons on any entity with a persisting notification (prepended, 359-367). The icon set comes from each notification type's `useDataState().hudIcon`:
    - line problems (no path, ≤1 station, double/incompatible stations, bad alternative terminal; notifications/types/line_warning.script.tl:145-158, 210)
    - useless stop (line_station_warning.script.tl:94-107, 155)
    - vehicle no-path / blocked (vehicle_warning.script.tl:87-101)
    - vehicle condition / repair (vehiclecondition.script.tl:71-85)
    - stuck vehicle (stuck_vehicle.script.tl:14, 53)
    - terminal full / overcrowding (overcrowding.script.tl:9, 27)
    - unreachable station (station_useless.script.tl:14, 43)
    - town warnings (town_warning, town_rating_warning*)
    - industry closing, no road connection, cargo return-to-sender (cargo_rtc_warning)
    - subvention, prospection, marketing, greenify
    - There is no notification type for unprofitable lines/vehicles (types/ listing; grep "profit" finds nothing relevant).
  - Floating money: costs and income popups with SFX (engine; `showCosts`/`showIncome`/`incomeSFX`/`costsRenderDistance`, selector_react_util.tl:219-222).
  - Ephemeral effects (game scripts with guiUpdate):
    - cargo icons flying on load/unload (hud/cargo_flow.script.tl:43-164)
    - happy/sad emote on passengers whose happiness changed, player lines only (hud/happy_change_display.script.tl:190-260)
    - leaves on greenified industries plus a sound (greenification_display.script.tl)
    - megaphones spreading over a town during marketing plus a sound (marketing_display.script.tl)
- Hover-only: `DefaultEntityToolTip` (main/game_tooltips.tl:145-223):
  - the entity name (or a delegate: carriage → vehicle, crossing / double slip, bridge/tunnel type, HQ, fun element)
  - plus the `iconExplainTooltip` text of each persisting notification (Notification3DTooltip, 122-143)
  - this is the only map-level place where the meaning of a warning icon is spelled out
  - `TerrainTooltip` (225-285): height, noise or pollution level under the cursor when nothing is hovered
- Click behaviour:
  - HUD icons are `setMouseTransparent(true)`. `HudIconChildConfig.selectorSupport` defaults to true at the root (scripts/builtin.d.tl:1272), so hovering or clicking an icon selects the underlying entity.
  - The Selector `onSelect` (selector_react_util.tl:106-127) fires `selectEntity`, and `view_manager.openWindow` opens the entity window (vehicle, station, town, industry, line …; entity_window/view_manager.tl:617-626). `DisableFeatures.OpenEntityWindow` suppresses this.
  - Markers fire `selectMarker`. Clicking empty ground fires `selectNothing {stack=true}` (128-131).
  - Edges are not selectable. Base nodes are selectable only if they are a switchable double slip or a configurable traffic light (133-149).
  - Default (no layer) is non-stacking with the mouse, so a new window replaces the old one (`stack = allowStacking==nil and isGamepad`, 108). Inside layers, windows stack.
- Inspector (gamepad): `InspectorSelector` / `InspectorTool` (selector_react_util.tl:243-388). Toggled with `IA_INSPECTOR`, exited with `IA_ABORT` (298-306). Gamepad only (auto-deactivated in mouse mode, 309-315).

### 1.5 Other HUD masters that reuse layer masters (context)
The town window tabs switch the map HUD to the matching layer master: Supplies → cargo flow with passengers and percentages; Traffic; Happiness; Delivery; Noise; Pollution (entity_window/entity_window_hud.tl:551-588).

Other HUD masters exist per window, outside this sub-scope: industry, station group, line, vehicle, maintenance, subvention, perk, town building, construction (`constructionHudIconMaster.tl`) and line/vehicle manager (`manager_hud_util.LineVehicleManagerHudIconMaster`).

### 1.6 Callouts (screen-space popovers, not map)
- `CalloutContainer` (main/callout_container.tl:6-145) is a single-slot popover host with an `open/close` API, an optional show delay (106) and KeepInside positioning. Reached via `gameCtx.calloutContainerRef` (game_context.d.tl:68).
- `ToggleCalloutButton` (main/callout_react_util.tl:62-196) is a toggle button that opens the callout. It closes on `IA_MENU_BACK`, `IA_CLOSE_TOPMOST_WINDOW` (forwarded), when the parent becomes invisible (heartbeat check, 164-169), or on toggle.
- `DefaultCalloutWrapper` (198-220) draws content plus a down arrow.
- Used by pause_menu.tl:323, notification_log.tl:452, content_card.tl:78, menu_category_util.tl:385, script_param_util.tl:164/260, celebrations, and menus.

### 1.7 Particles
`particle_react_util.tl`: 2D particle emitters for company level-up and unlock animations (`makeCompanyLevelUpParticles` 6, `makeUnlockAnimationParticles` 27, `makeParticleSystem2dEmitter` 117). These are celebration feedback, not status.

### 1.8 Mod hooks found in this area
| Hook | Where | Use |
|---|---|---|
| `MainModButtonAreaExtension` (`RegisterExtensionPoint0`) | main/main_mod_button_area.tl:170, rendered next to the layers button at game.tl:552 | place for custom quick-toggle buttons (HUD filters, custom layers) |
| `react-replacement-config` → `ReplaceRecipe` (GloballyReplaceRecipe by recipe id, before init) | main/bootstrap_game.tl:6-51; main/react.lua:445-465 (`CallOriginalRecipe` allows wrapping, not for builtins) | replace or wrap any exported recipe: `ExpandableLayerButton`, `HudIconMasterGame`, `HudIconMasterBase`, `TownHudIcon`, `DefaultEntityToolTip`, `TerrainTooltip`, `layer_*.Layer`/`Legend`/`HudIconMaster`, `TownRatingHudIcon`, `NotificationHudIcons`. Not reachable (module-local): `ButtonRidge`, `LayerWindow`, `createStationIcon`, `StockHudIcon`, `HudIconManagerTerrain/Towns/Speed/Mobility` |
| Construction `hudIconScript` | api/type.d.tl:1687; hud_icon_toolbox.tl:243-252 | per-construction custom HUD icon (e.g. a mod station asset) |
| `hud_gui_config.gres.lua` render distances and vehicle icon offsets | hud/hud_gui_config.gres.lua:5-23 | data override: HUD density/visibility |
| `layer_colors.gres`, `gameplay_colors.gres`, `selection_colors.gres` | loaded in each layer (e.g. layer_cargo.tl:17-18) | recolour layers and legends |
| Notification types (`.res.lua` + `.script.tl` with `useDataState().hudIcon`) | game_mechanics/notifications/types/* | new persisting notification → automatically gets a map HUD icon and hover text through `NotificationHudIcons` / `DefaultEntityToolTip` (registration path needs verification) |
| GUI game scripts (`*.gs.lua` with `guiUpdateScript`) | hud/*.gs.lua | add map effects via `api.gui.spawnEphemeralHudImage[OnPath]` |
| `RadialMenuExtension` | main/radial_menu_extension.tl:6 | gamepad radial entry (e.g. extra layer) |

## 2. Task flows (mouse unless noted; C = clicks, S = screens/windows, X = context switches)

1. Open a specific data layer: click the layers button (1) → click the layer icon (2). 2 C, 1 S. Hotkey `IA_TOGGLE_LAYER_*`: 1 key (key unknown; shown only as a modifier in the hover tooltip). There is no way to pick a layer by name: icons only, labels on hover.
2. Switch layer A → B: 1 C (ridge stays open) or 1 key.
3. Close the layer and return to the normal view: click the active icon (1) or the window X (1; the ridge stays expanded, so another click on the layers button collapses it) or `IA_MENU_BACK`.
4. Find stations where passengers are unhappy:
   - Default HUD shows the waiting count, and its colour turns orange/red if any or most are unhappy. 0 C, but colour only, and only within the camera-height window (cutoff 30, threshold 150).
   - The exact unhappy count needs the Passenger Satisfaction layer: 2 C.
5. Check cargo waiting at a station: not on the map HUD (passenger-only station icon). Click the station → station window (1 C, 1 S, then tab navigation; see entity-window inventory).
6. See why a vehicle or station shows a warning icon:
   - hover the entity → tooltip with `iconExplainTooltip` (0 C, hover)
   - click → entity window (1 C)
   - there is no list of all warning icons on the map (only the notifications ridge or log, covered elsewhere)
7. Find unprofitable lines from the map: impossible; no HUD or notification signal exists. Use the Lines statistics or manager (other inventory).
8. Show cargo delivery quality for one cargo type: layers (1) → Cargo Satisfaction (2) → open combo (3) → pick cargo (4). 4 C. Resets to All Cargo every time the layer is reopened.
9. See cargo flow for one cargo type: not possible; Cargo Flow has no filter. Must use Cargo Satisfaction (different data) or the industry window.
10. Show the passenger catchment of all stations: layers (1) → Infrastructure (2); the Passengers area is default. Cargo catchment: +2 C (combo). Maintenance coverage: +2 C.
11. Show speed limits of own track only: layers (1) → Infrastructure (2) → Speed Limit combo (3) → Player Owned (4). 4 C, reset on reopen.
12. Analyse a single town's passenger flow: layers (1) → Passenger Flow (2) → town combo (3) → scroll and pick from the alphabetical list (4+). Clicking the town on the map opens the town window instead of filtering the layer.
13. Hide bus icons / reduce clutter: layers (1) → HUD Filters (2, closes any data layer) → toggle Road Vehicles (3) → close (4). 4 C, persisted. No hotkey.
14. Turn off floating income/cost popups: same path as 13. 4 C.
15. Investigate a town's low rating:
    - town window → rating bar click → `openLayerRidge` with the matching layer and `stack=true` (town_util.tl:654-704). 2 C from the map (town click + bar click), 2 S.
    - alternatively the town window's own tabs switch the map HUD (entity_window_hud.tl:551-588).
16. Inspect a noisy building: town-building window → noise bar click opens the Noise layer (town_building.tl:186). 2 C.
17. Use a layer while building: in the construction menu, press `IA_TOGGLE_LAYER_BUTTON_RIDGE[_CONSTRUCTION]` or click the layers button → the layer stays as an assist overlay (ConstructionMenuAssist mode, layers_button_ridge.tl:590). Leaving construction collapses the ridge and clears the layer (505-512).
18. Gamepad:
    - radial menu → Layers (game_bar.tl:80-89), then D-pad up/down to cycle layers (`switchToPrevious/Next`), `IA_OPTION1/2` for the layer checkboxes and combos (layer_passenger_flow.tl:173-174, layer_infrastructure.tl:212)
    - Inspector mode via `IA_INSPECTOR`

## 3. Friction findings

| # | Finding | Evidence | Impact |
|---|---|---|---|
| F1 | No map signal for unprofitable lines or vehicles. There is no notification type for profitability, so nothing appears in the HUD, the notification icons or the tooltips. The player has to go to statistics. | notifications/types/ (no profit type); hud_icon_toolbox.tl:359-367 shows only persisting notifications | High |
| F2 | Station HUD is passenger-only. Cargo waiting or overflowing at stations has no at-a-glance count; the station icon is built only from the passenger cargo type. | hud_icon_toolbox.tl:112-143, 234-238 | High (verify in game) |
| F3 | Layer options are not persisted: cargo filter, area combo, speed-limit restriction, town and transport checkboxes all reset on every open. Repeated analysis costs +2-4 clicks each time. | layer_cargo.tl:276-281; layer_infrastructure.tl:159-164; layer_passenger_flow.tl:162-168 | Med |
| F4 | Only one layer at a time, and HUD Filters counts as a layer. Changing a HUD filter closes the active data layer, so filters cannot be tweaked while watching e.g. traffic. | layers_button_ridge.tl:173-184, 427-437 (singleton window 125/228) | Med |
| F5 | HUD Filters has no hotkey and needs 2 clicks to reach plus 1 to close. There is no one-key "declutter" or "warnings only" mode. | layers_button_ridge.tl:427-437 (no inputActionId) | Med |
| F6 | Layer picker is icon-only. Names and hotkeys appear only on hover (`tooltip`, `tooltipModifierInputAction`), so 11 similar icons are poorly discoverable. | layers_button_ridge.tl:262-267, 533-537 | Med |
| F7 | Opening a layer always takes 2 clicks with the mouse. The ridge first has to be expanded; it does not remember the last layer, and there is no one-click "last layer" option. | layers_button_ridge.tl:541-550 (expand only, `initialButtonState=nil`) | Med |
| F8 | Warning icons are explained only on hover over the single entity (`iconExplainTooltip`). There is no legend for the icon vocabulary (≈20 notification HUD icons) and no aggregation on the map. | game_tooltips.tl:122-143, 196-208 | Med |
| F9 | Unhappy-passenger count is hidden in the default HUD (colour only, colour-blind unfriendly). The number appears only in the Passenger Satisfaction layer. | hud_icon_toolbox.tl:113-119 vs layer_public_transport.tl:355-378 | Med |
| F10 | Cargo Flow layer has no cargo filter and always excludes passengers. Cargo Satisfaction has a filter, which is inconsistent. | layer_cargo_flow.tl:302-356, 309 | Med |
| F11 | HUD visibility depends on camera height (lower cutoff 30, threshold 150, LOD 3000) and town districts are never shown by default, so zoomed-out overviews lose station and vehicle status. There is no setting for it. | hud_react_util.tl:5-8, 53-153 | Med |
| F12 | Terminal numbers are shown only for the selected station, so there is no overview of which platforms are used. | hud_icon_toolbox.tl:224-231, 335 | Low |
| F13 | Passenger Flow town selection only via combobox. A map click opens the town window instead of focusing the layer on that town. | layer_passenger_flow.tl:240-250, 209 | Low |
| F14 | Legends are coarse ("Low/High", "Good/Bad", iterative 1..4) with no numeric thresholds, e.g. the satisfaction thresholds 1/10/25/50 % are not shown. | layer_react_util.tl:131-171; layer_public_transport.tl:343-352 | Low |
| F15 | Closing via the window X leaves the ridge expanded (mouse). A second click on the layers button is needed to tidy up. | layers_button_ridge.tl:91-106 (closeLayerRidge only for gamepad) | Low |
| F16 | Layers stack entity windows: clicking the map in a layer opens stacked windows (`allowStacking=true`), unlike the default view, so windows pile up during analysis. | layer_traffic.tl:436 etc.; selector_react_util.tl:108 | Low |
| F17 | No extension point for the layer list. Mods cannot add a layer button without replacing `ExpandableLayerButton`. | layers_button_ridge.tl:316-438 | Low (modding) |

## 4. Improvement opportunities

| # | Proposal | Saving | Moddability |
|---|---|---|---|
| I1 | Quick-toggle bar next to the layers button: one-click toggles for HUD filter groups (vehicles per carrier, costs/income, events, cargo flow), a "declutter" preset and a "last layer" button. | HUD filter changes 4 C → 1 C; reopening the last layer 2 C → 1 C | Plugin into `MainModButtonAreaExtension` (main_mod_button_area.tl:170; game.tl:552). Writes `api.gui.game.setGuiSaveData("", …hudFilter)` exactly like layer_hud_filter.tl:58-82; opens layers via `react.fireEvent(nil,"openLayerRidge",{layer=<id>})` (layers_button_ridge.tl:447-462). |
| I2 | Richer station HUD: always show the unhappy count as a number (today only the colour shows it), the waiting cargo per type and an optional terminal-usage strip. | Satisfaction check 2 C → 0; cargo-waiting check 1 C + window → 0 | Replace or wrap `hud_icon_toolbox.HudIconMasterGame` (exported, hud_icon_toolbox.tl:160) via `react-replacement-config` (bootstrap_game.tl:12-51) with `CallOriginalRecipe` plus an extra child. Data: `api.engine.util.cargo.getCargoQualityDataAtStationGroup(entity, cargoTypeId)` per cargo (used at 234). Needs a perf check (runs per icon per step timer). |
| I3 | Unprofitable line / vehicle warning on the map: a new persisting notification type whose `useDataState` returns `hudIcon` + `iconExplainTooltip`, attached to the line's vehicles and stations. | Discovering a loss-maker: statistics navigation (≥3 C) → 0 C at a glance | Needs verification: the pipeline is generic (`NotificationHudIcons`, notification_react_util.tl:147-167; tooltip game_tooltips.tl:172-208), but how the notification types and sim scripts are registered (`.res.lua` / `.sim.script.tl`) needs checking. Alternative: a HUD-only overlay by wrapping `HudIconMasterGame` and reading line profit from the engine (API availability to verify). |
| I4 | Persist layer options (cargo filter, area, restriction, town, checkboxes) and remember the last active layer. | Repeat analysis 4 C → 2 C (or 1 key) | Replace the exported `layer_cargo.Layer`, `layer_cargo_flow.Layer`, the Infrastructure/PassengerFlow module returns (`SpeedLayerTagWrapper`, `MobilityLayerTagWrapper`) with copies whose state is seeded from `getGuiSaveData`. Inner recipes are module-local, so the whole layer content has to be copied. |
| I5 | Decouple HUD Filters from the single-layer slot, e.g. as a popover through `ToggleCalloutButton` (callout_react_util.tl:62) in the mod button area. | Filter tweaks no longer close the data layer (saves 2 C per round trip) | Builds on I1: the filter UI only writes GUI save data, and the default and layer HUDs read it via `makePreFilter` (selector_react_util.tl:43). Note: layer HUD masters do not apply `preFilter` from hudFilter (they pass their own prefilter), so filters affect only the default HUD and the ephemeral effects. Needs verification of the desired behaviour. |
| I6 | Labelled layer ridge (icon + name + hotkey) and a cargo filter in Cargo Flow. | Discoverability; Cargo Flow per cargo 2 → 4 C, newly possible | Replace `ExpandableLayerButton` (exported; `ButtonRidge` is local, so the whole file has to be copied). Cargo filter: copy `layer_cargo_flow.Layer` and set `cargoConfig.cargoTypes` (layer_cargo_flow.tl:201-207). |
| I7 | Hover tooltip shows more status (vehicle: line, load %, age/condition; station: waiting per cargo; industry: production) so no window has to be opened. | 1 C + window → hover | Replace `game_tooltips.DefaultEntityToolTip` (exported, game_tooltips.tl:145) and keep the notification part. |
| I8 | Zoomed-out status: raise or extend the HUD visibility thresholds, or add a "warnings-only far LOD" mode. | Fewer camera moves to spot problems | `hud_gui_config.gres.lua` render-distance scales (data override). Camera thresholds are fields on the `hud_react_util` module table (hud_react_util.tl:5-8); overriding them from a mod at load needs verification of module caching (`ug_require`). How visibility filtering works is engine-side (`HudIconManagerConfig`, builtin.lua:370); the extent is unknown. |
| I9 | Legend with numbers (satisfaction %, dB, speed values). | Interpretation time | Replace the exported `layer_*.Legend` recipes (e.g. `layer_public_transport.Legend`, 535; `layer_cargo.Legend`, 205; `layer_traffic.Legend`, 365). |
| I10 | Warning-icon legend / aggregate: a small panel listing the counts of each active HUD warning type, click to cycle the camera to the entities. | Finding problems: free scan → 1-2 C | A `MainModButtonAreaExtension` plugin. Data from `notification_util.externalGetNotificationsStateNative` + `getPersistingEntity2NotificationFromNative` (as in notification_react_util.tl:89-114). The camera jump API needs checking (`api.gui` renderer). |
| I11 | New hotkeys (HUD filter, last layer, declutter). | 2-4 C → 1 key | Probably not feasible: input-action ids such as `IA_TOGGLE_LAYER_*` are defined outside the shipped scripts (engine/config). Registering new IA ids from a mod needs in-game or engine verification. Workaround: reuse existing IA ids inside a focused widget, or rely on mouse buttons from I1. |
