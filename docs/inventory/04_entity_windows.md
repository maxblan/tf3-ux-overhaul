# 04 – Entity windows (what opens when you click something on the map)

Scope: `SCR/game/gui/gui/entity_window/**` (+ brief look at `gui/debug_panel`). All paths below are relative to `SCR/game/gui/gui/` unless they start with `game_mechanics/` (= `SCR/game/game_mechanics/game_mechanics/`).
"EW" = entity window. "Card" = `content_card.ContentCard` (main/content_card.tl:207), a box with a permanent part and an optional collapsible part (chevron).

---

## 0. Architecture (applies to all windows)

### 0.1 Opening / dispatch
| Step | Code |
|---|---|
| Map click → `builtin.Selector.onSelect` fires React event `selectEntity {entity, stack}`. For mouse users `stack = false` (stack is only true by default for gamepad, or when the selector was created with `allowStacking=true`, as in the data layers) | main/selector_react_util.tl:106-109, 123 |
| `ViewManager` recipe (registered recipe "ViewManager") listens to `selectEntity`, `selectViewKey` (non-entity windows: missions, subsidies), `closeAllWindows` | entity_window/view_manager.tl:524-642 |
| `openWindow()` maps the clicked entity to a "view entity" via `view_manager_util.wouldCreateView` (carriage → owning vehicle; subconstruction → construction → industry/warehouse/station group; station → station group; base node only if double-slip-switch or traffic-light capable…) | view_manager_util.tl:92-313 |
| **Depots without maintenance pool do not get an EW** – they fire `openVehicleManager {openWithDepotEntity}` (the full Line/Vehicle Manager) | view_manager.tl:559-567 |
| If `stack == false` → `closeAll()` removes every *unpinned* window (pinned ones survive only in mouse mode: `keepPinned = not isGamepadInputMode()`) and clears the whole tool stack | view_manager.tl:525-554, 581-584 |
| Pushes an `EntityDetailsTool` (one tool-stack entry per window, key = entity id) | view_manager.tl:339-456, 604 |
| Content: `make_entity_window.makeEntityWindowContent()` picks the content recipe by component type, in this priority order: (construction with `entityWindowScript` → custom script) → (construction with >1 subconstruction → **ConstructionWindow with tab header**) → Animal → TransportVehicle → Town → TownBuilding → Industry → SimPerson → Warehouse → VehicleDepot w/ maintenancePool → StationGroup → Line → RailroadCrossing → Signal → BaseNode (double slip / traffic light) → Bridge/Tunnel → CustomState (fun element, or model metadata `entityWindowScript`) → EmptyConstruction | entity_window/make_entity_window.tl:293-765 |
| Non-entity windows (`selectViewKey`): `"mission"`, `"subsidy_*"` | entity_window/make_non_entity_window.tl |

### 0.2 Window chrome (`EntityWindow`, wrapper recipe around `builtin.Window`, view_manager.tl:94-327)
- **Title** = entity name, **editable inline** (`titleEditable`, `onTitleChange` → `makeEntitySetNameCmd`), fallback title per type (e.g. "Vehicle", "Station").
- **Locate button** in title bar → `api.gui.camera.followEntity(entity, true)` (= *follow camera* for moving entities) + gui script event `entityWindow/locate` (view_manager.tl:263-271, 291-293).
- **Pin button**: only when input mode is keyboard/mouse (`pinnable = isMouseInputState`, :312). **Dragging the window auto-pins it** (`onMovedChange` → pinned, :318-322).
- **Close**: X button, `IA_MENU_BACK` (Escape / gamepad B) closes the focused window (:245-247); `uiCloseAll` (default key **Delete**, settings_keys_v3.lua:1082) → `api.gui.closeAllWindows()` (main/game.tl:228-235).
- **Auto-close** when the entity's revision changes (rebuilt/upgraded/deleted) (`entityRevisionCloseCondition`, :153-167).
- Re-selecting an already-open entity does not open a 2nd window; it **blinks** the existing one (:354-375, 98-120).
- Fixed size: 450×900 px design size (entity_window_sizes.lua:3-4); `initialX = 1, initialY = 0` (exact placement of stacked windows → needs in-game verification).
- Sound effect on open from model/construction `soundConfig.effects.select` (view_manager_util.tl:49-151).
- **Context map mode** ("action function"): every window installs a map overlay via `params.setActionFn` while it is the active window (catchment area, line visualisation, cargo-flow arrows, custom HUD icons, layer config). Only the *active* (last focused) window's overlay is shown (view_manager.tl:122-142, 299-305).

### 0.3 How many windows / stacking / pinning
- Mouse map click: **always exactly one unpinned window** (all other unpinned ones are closed) → to compare two entities you must pin (or drag) the first window.
- Links *inside* windows (line name in vehicle window, line in station window, supplier name in industry window, vehicle name in line window, resident destinations…) use `stack = true` → windows accumulate. No upper limit in code.
- Gamepad: always stacks, but cannot pin; `closeAll` also removes pinned windows in gamepad mode.
- Data layers (`layers/layer_*.tl`) create their selector with `allowStacking = true` (layer_cargo.tl:318 etc.).
- **Any tool push without stacking clears the tool stack → closes all unpinned EWs**. This happens for `openVehicleManager` (LVM; manager_window.tl:8447-8490 → `push(ManagerTool, nil, …)` without `allowStacking`, builtin.lua:1383-1389). So "Manage Line", "Send to Line", "Manage Vehicles" close the window they were clicked in (unless pinned).
- Pinned windows are handed to the "default tool" (`handoverToPinned`, view_manager.tl:404-440, 499-513).

### 0.4 Common building blocks (entity_window/entity_window_util.tl)
| Recipe | Line | Notes |
|---|---|---|
| `ActionButtonBar` | 1187 | bottom bar. **Primary buttons = icon + text; secondary = icon only, label only as tooltip** (`makeActionButtonElement`, 1116-1185) |
| `MaintenanceBar` | 143 | "$X/Year" upkeep/running cost line above action bar; hidden when 0 |
| `NotificationWidget` | 2129 | persisting notifications for this entity as coloured cards at top of window; clickable (`dataState.onClick`) |
| `CombinedStockGroupedCounts` | 732 | Input/Output stock cards; collapsible part injected by caller (suppliers/consumers tables) |
| `EntityDiagramWidget` | 911 | logbook/account charts (years slider optional) |
| `ContentWidgetScrollContainer` | 2464 | vertical scroll area holding the cards |
| `EnterCockpitButton` | 1726 | pushes `FreeCamTool` with `cockpitCameraForEntity` |
| `SpeedIndicator` | 2296 | overlay on vehicle renderer |
| `makeConfigureOnClickFunction` | 1796 | "Configure" → fires `setModuleBuilderEntity` + `constructionMenuSetTab {tabIndex=9, allowStacking=true}` (opens construction menu module builder) |
| `RatingBar`, `ProgressDisplay`, `PassengersWidget`, `InhabitantsTable`, `WorkersTable`, `VehicleTable`, `NoiseAndPollution`, `SubconstructionBalance` | 33, 1810, 1659, 1511, 1602, 1948, 2488, 2165 | |

- Collapsible cards: `content_card.makeContentCardsCollapsibleFunctions(state, onlyOneExpandable=true)` (main/content_card.tl:457-477) is used by **every** window → **accordion: opening one collapsible closes the others**; state is per-window `useState` → **reset each time the window is reopened**.
- Info callouts (`initialCalloutText…`) are all set to `""` (keys commented out everywhere) → effectively disabled (content_card.tl:70-75 hack).
- Updates: most data via `engine_react_util.useStepState` (every sim step) or `useStepStateTimer`; town ratings via `useStepStateParallel*` (parallel scripts).

### 0.5 Extension points (all `react-plugin` res files: `type = "react-plugin ::<EP>"`, `data = {filePath, condition, order}`; consumed by `gui_react_util.usePlugins`, main/gui_react_util.tl:513-565, sorted by `order`, `condition(params)` filters)
| Extension point | Default plugins (order) | Inserted where | Remarks |
|---|---|---|---|
| `VehicleEowExtensionPoint` (vehicle/vehicle_eow.script.tl) | Notification 0, Basics 10, Condition 50, Balance 70 (player-owned) | scroll area below 3D renderer | action bar NOT extensible |
| `LineEowExtensionPoint` | Notification 0, ColorPicker 10, Basics 20, Transported 30 (not foreign), Vehicles 50, IncomeGraph 60 (not foreign) | whole window | |
| `StationGroupEowExtensionPoint` | **none** | after notifications, before waiting halls/terminals (station_group.tl:864) | empty slot – ideal for mods |
| `TownEowExtensionPoint` | Notification 0, Level 10, [hard-coded TownInformationWidget 30], Charts 40 (Overview tab only), MapEditorSupplies 50, [hard-coded Statistics 60, Supplies tab only], DebugGraph 70 (disabled) | via `insertHardcoded` (town.tl:1272-1278) | |
| `TownEowEditorExtensionPoint` | 4 sandbox editor cards | "Editor" tab (only exists if any plugin passes) | |
| `TownBuildingEowExtensionPoint` | **none** | top of window | empty slot |
| `IndustryEowExtensionPoint` | Notification 0, ProductionRules 10, Boosters 20, Stocks 30, BalanceChart 40 | whole window | |
| `WarehouseEowExtensionPoint` | Stocks 20, Diagram 30 | | |
| `MaintenanceStationEowExtensionPoint` | Pool 20, Balance 30, Statistics 40, Vehicles 50 | | |
| `PerkEowExtensionPoint` | Notification 0, Basics 10, Stocks 40, Booster 50, PersonCapacity 60, MaintenanceBar 70 | | perk window is used by constructions' `entityWindowScript` (e.g. game_mechanics/emission/pollution_cleanup_facility_hud.script.tl:5,124) |
| `SimPersonEowExtensionPoint` | Locations 20, Happiness 30, Route 40 | | |
| `AnimalEowExtensionPoint`, `FunElementsEowExtensionPoint`, `EmptyConstructionEowExtensionPoint` | 1 each | | |

Other moddability hooks:
- Data-driven custom windows: construction `entityWindowScript` (make_entity_window.tl:328-351) and model metadata `entityWindowScript` for custom-state entities (:708-739).
- All window recipes are registered (`RegisterRecipe("VehicleWindow")`, `"LineWindowContent"`, `"StationGroupWindowContent"`, `"TownWindowContent"`, `"IndustryWindow"`, `"WarehouseWindow"`, `"ViewManager"`, wrapper `"EntityWindow"`, plugin recipes …) → replaceable with `react.GloballyReplaceRecipeBeforeInitInternal` (react.lua:445-457) and the original callable via `CallOriginalRecipe` (react.lua:459-467).
- `make_entity_window.makeEntityWindowContent`, `view_manager_util.wouldCreateView`, `selector_react_util.makeDefaultSelector`, `content_card.makeContentCardsCollapsibleFunctions` are plain module functions (not recipes) → only patchable by monkey-patching the shared module table (whether `ug_require` returns a shared, mutable table: **needs verification**).

---

## 1. Surfaces

### 1.1 ConstructionWindow (multi-subconstruction wrapper)
- **Recipe**: `ConstructionWindow`, make_entity_window.tl:117-276.
- **When**: the clicked construction has >1 subconstruction of type Warehouse/Industry/Station/Depot/Maintenance building (e.g. a station with an integrated depot, combined road/rail station). Station groups are first resolved to their first station's construction (:311-323).
- **Status**: a North tab bar with one tab per subconstruction, label = type only ("Train Station", "Road Station", "Tram Station", "Port", "Runway", "Helipad", "Depot", "Maintenance Building", "Warehouse", "Industry"; :46-102), sorted by type. Content of the selected tab is the normal EW content of that subconstruction.
- **Actions**: switch tab (click / `IA_TABLEFT`/`IA_TABRIGHT`, :250-251). Re-clicking another part of the same construction switches the tab (`openEntityEntry` event, :215-218).
- **Notes**: tab labels don't carry names or status (e.g. no overflow warning on the "Train Station" tab).

### 1.2 Vehicle window
- **Recipe**: `VehicleWindow`, vehicle/vehicle.tl:135-639; plugins in vehicle/vehicle_eow.script.tl.
- **Entry**: click vehicle or any carriage on map (carriage → owning vehicle, view_manager_util.tl:185-187); vehicle name in line window vehicle table (line_eow.script.tl:105-110, stacked); maintenance-station vehicle table; statistics vehicle list (statistics/statistic_vehicles.tl:40, stacked); condition icon in LVM (line_vehicle_mgmt/vehicle_react_util.tl:66-68, **not stacked**); notifications (vehiclecondition.script.tl:58).
- **Status at first glance (top→bottom)**:
  1. 3D renderer of the vehicle (`EntityRendererComponent`) with overlays: specialization bubbles + modifier percentages (speed/pollution/noise/comfort) top-left (vehicle.tl:27-132, 271-286); speed indicator bottom-right (:260-270); "Enter Cockpit" button bottom-left (:255-259).
  2. Notification cards (order 0).
  3. **Basics card** (vehicle_eow.script.tl:988-1069): line colour + line name **button** (or depot icon + "Going to Depot"/"In Depot"), next stop name with tooltip "Stop x of y" (`VehicleTarget`, :36-84), line **rate** and **frequency** icons (tooltip has the value text) (:888-986).
  4. **Load card** (`VehicleCarriage`, :854-886): current cargo/passengers with loading indicator; "Average Happiness" / "Average Remaining Delivery Time" % indicator (:618-675). Collapsible (player-owned passenger vehicles): `PassengersWidget` list.
  5. Noise & pollution totals card.
  6. **Condition card** (player-owned): rating bar (condition %, trend) (:1108-1137); collapsible: maintenance log (`VehicleMaintenanceLog`).
  7. Vehicle-type card (`VehicleInfoType`, incl. "Change Color" button :143); collapsible: details (top speed, loading speed, noise, pollution, comfort per part).
  8. **Balance card** (player-owned): income vs running costs chart, 16 years (:1195-1226).
  9. Maintenance bar: running costs per year (vehicle.tl:292-299).
- **Hidden**: passenger list, maintenance log, per-part details (each behind a chevron, accordion); values of rate/frequency/speed only in tooltip; full stop list/timetable not available.
- **Actions** (action bar, only if owned by player or unowned; vehicle.tl:391-548):
  - Primary: **Send to Line** → `openVehicleManager {openWithVehicleEntities, sendToLineMode=true}` (closes this EW unless pinned, see 0.3).
  - Secondary (icon-only): **Reverse** (`makeVehicleReverseCmd`), **Start/Stop** (`makeVehicleSetStoppedByUserCmd`), **Clone** (`duplicateVehicles` event → buys a copy and assigns it via `findBestLineAndDepotForVehicle`, manager_window.tl:8493-8560 – target line needs in-game verification), **Replace** (toggle; opens Vehicle Store window `replaceVehicles`, EW stays open), **Modify** (toggle; rail/tram only; `modifyVehicles`), **Send to Depot** (`makeVehicleSendToDepotCmd`; failure → feedback "Vehicle could not be sent to depot."), **Sell** (`makeVehicleSellCmd`, **no confirmation**; protected entities show feedback).
  - Title bar locate → camera follows the vehicle. Cockpit button. Horn: `cockpitCameraHorn` (key H) while window focused (:550-552).
  - Line name button → opens line window (stacked) (vehicle_eow.script.tl:958-964).
- **Map context**: vehicle HUD icons, catchment of vehicle, the vehicle's line drawn (`LineViewer`, selectable) (vehicle.tl:561-625).

### 1.3 Line window
- **Recipe**: `LineWindowContent`, line/line.tl:73-220; plugins line/line_eow.script.tl.
- **Entry**: line button in vehicle window; `LineStopButton` in station window (station_group.tl:170-221); line names in town Happiness/Delivery/Noise/Pollution tabs (game_mechanics/towns/town_react_util.tl:1631, 1713, 2079); LVM/line list (line_react_util.tl:265); line warning notifications (line_warning.script.tl:199). Lines are not clickable on the map in the default selector (only in LineViewer when `selectable=true`, e.g. station window overlay).
- **Status**:
  1. Notifications (line warnings).
  2. Line colour picker (`LineColorPicker`, always visible).
  3. **Basics card**: cargo types currently transported (`LineCargoInfo`, "Currently No Items Transported"), **rate** and **frequency** (values in tooltip) (:489-534, 542-602); noise/pollution totals.
  4. **Transported card**: "Last Year" number; collapsible: transported chart (:604-638).
  5. **Vehicles card**: sortable `DataTable` with columns *Vehicle* (locate button + name button + vehicle image) and *Age* ("x of lifetime (y remaining)" / "Lifetime Reached") (:99-247).
  6. **Balance card**: income vs running costs chart (:658-690).
- **NOT shown**: list of stops/stations, waiting passengers/cargo per stop, load factor, per-vehicle condition/profit/load, timetable, profit number as text (only chart).
- **Actions** (player-owned): primary **Manage Line** → `openVehicleManager {openWithLineEntity}` (LVM; closes EW unless pinned) (line.tl:137-150); secondary **Reservation priority** toggle group (Standard/High/Very High, rail lines supporting reservation) (:17-71, 152-158). Inline rename via title. Click vehicle name → vehicle window (stacked); locate button per vehicle.
- **Map context**: line drawn (not selectable), line HUD: vehicles of this line show cargo load icons, stations/towns of the line highlighted (line.tl:171-211; entity_window_hud.tl:629-712).

### 1.4 Station (station group) window
- **Recipe**: `StationGroupWindowContent`, station_group/station_group.tl:618-1067 (no default plugins; EP exists).
- **Entry**: click station/platform/stop (→ station group; possibly wrapped in ConstructionWindow tabs); station notifications (line_station_warning.script.tl:145); statistics stations list.
- **Status**:
  1. Notifications of the station group **and** of every station in it (:858-862).
  2. (plugin slot – empty)
  3. **Waiting hall card(s)**: used/capacity + passenger icon; red + "terminal full" icon with tooltip "Some passengers may leave because the station is overloaded." when overflowing (:60-168, 869-883).
  4. "Terminals" title card, then per terminal a card (`TerminalsAndStops`, :489-540):
     - `TerminalBar`: terminal number indicator, type bubble ("Passenger", "Passenger and Cargo", cargo class name with colour, "All Cargo Types"), terminal length, used/capacity, overflow highlighting (:223-303, 414-454).
     - Per line stopping there (player lines only, :700): `LineStopButton` (line colour + "Line – next station") → opens line (stacked); waiting **passenger** count + unhappy count (emote icon); if a line stops several times: rows "via <next station>"; **"Terminal is too short for some vehicles." alert icon** (tooltip) (:317-412).
     - **Hover tooltip** on counts = destination breakdown "[n] Station count" (:648-691).
  5. **Statistics card** (player-owned): loaded/unloaded chart (:983-1008).
  6. Maintenance bar (upkeep/year) (:1035-1042).
- **Hidden / missing**: destinations only on hover; **cargo waiting is not shown per stop** – only `passengerCargoTypeId` is queried (:704-710) although the API supports any cargo type (`getCargoQualityDataAtStop/AtTerminal(…, CargoTypeId)`, apidef/api/engine/util.d.tl:758-764); capacity usage only computed for `isStationOfType(stationId,false)` (:641-646; semantic of `false` → needs verification, probably passenger stations only); no catchment list (towns/industries served), no frequency per line, no vehicles currently at station, no link to the town.
- **Actions**: **Configure** (only single-station constructions with slots, player-owned and modifiable) → construction menu module builder (:1044-1055). Line buttons. Statistics chart can be focused with IA_SELECT (gamepad).
- **Map context**: catchment area (cargo+person), all lines serving the station drawn and selectable, station-group HUD icons incl. vehicle cargo load icons (:903-979; entity_window_hud.tl:350-430).

### 1.5 Town window
- **Recipe**: `TownWindowContent`, town/town.tl:1145-1342; `TownInformationWidget` :835-1143; plugins town/town_eow.script.tl; rating pages in game_mechanics/towns/town_react_util.tl.
- **Entry**: click town label/HUD icon or town hall; town warnings (town_warning.script.tl:44); statistics towns list.
- **Status**:
  1. Notifications.
  2. **Town level card** (`TownLevelWidget`, town_eow.script.tl:26-114): level name, population (residential capacity), growth-trend icon (prio_high / very_high), progress bar to next level (**percentage only in tooltip**), growth level text coloured ("Town Development Inactive" when disabled). Collapsible: `TownPopulationWidget`.
  3. **Overview card = dashboard of 8 rating buttons** (`TownInformationDash`, town.tl:671-743): Supplies, Bonuses, Reputation, Happiness, Delivery, Traffic, Noise, Pollution – each icon+name, **rating level only as colour class** (`TownRatingIconWithText`, town_react_util.tl:2225-2278), no numbers.
  4. **District Sizes chart** (only on Overview, `conditionTownCharts`, town_eow.script.tl:418-443).
- **Behind clicks**: clicking a rating button switches the card into tab mode: back-tab + 8 rating tabs (`TownInformationTabs`, :759-833), page = detail widget + info hint + rating chart (not for Bonuses). Map layer switches to traffic / passenger satisfaction / cargo satisfaction / noise / pollution / supplies layer with a fullscreen legend (:990-1023). Supplies tab additionally shows a **Statistics card** with **Destinations | Suppliers** toggle (`TownDestinationsAndSuppliers`, :603-669, 1248-1270): sortable tables (destination name with Shop/Work/Line-Usage; supplier name, cargo, received), names open windows (stacked) + locate buttons; Suppliers mode turns on 3D cargo-flow arrows (:880-904, 1036-1048). Happiness/Delivery tabs list lines with stats (line names open line window). Noise/Pollution tabs have an expandable "lines" list that also toggles line drawing (`setLinesExpandedState`).
- **Actions**: none besides navigation (no action bar). `IA_MENU_BACK` returns from a rating tab to Overview instead of closing (:1281-1287). Sandbox: separate "Editor" tab (cargo demand, target district capacities, district tool, ratings sensitivity).
- **Map context**: Voronoi town area highlight, per-tab layer, town HUD, lines stopping in the town (Overview + tabs where expanded) (:844-857, 1050-1123).

### 1.6 Industry window
- **Recipe**: `IndustryWindow`, industry/industry.tl:52-431; plugins industry/industry_eow.script.tl; production widgets entity_window/industry_react_util.tl.
- **Entry**: click industry building; supplier/consumer tables of other industries/towns (stacked); statistics industries list; subsidy windows (subventions_gui.tl:287, 311).
- **Status**:
  1. Notifications.
  2. **Production card** (`ProductionRulesWidget`, industry_react_util.tl:559-615): per rule inputs → outputs with icons, current consumption/production, annual max (tooltip), rule progress bar, duration incl. delivery-time effect, level/"Max."; "Industry is expanded to it's full potential." / "Industry is blocked from further expansion." (+ red plot triangles on map, industry.tl:55-144, 317-327).
  3. **Boosters card** (not foreign): booster rules + workers (collapsible: workers table).
  4. **Input Stocks / Output Stocks cards** (compact stored/capacity bars, quality tooltip).
  5. **Cargo Flow chart** (consumed/produced/destroyed).
  6. Action bar: **Configure** (only player-owned, modifiable) (:412-421).
- **Hidden**: **Suppliers table** = collapsible of Input Stocks; **Consumers table** = collapsible of Output Stocks (industry_eow.script.tl:768-796). Tables list *every* industry/town on the map that matches the cargo (`industry_util.forEachMatchingStocklist`, main/industry_util.tl:603-649) with columns Supplier/Consumer, Cargo, Received/Supplied (sortable; refreshed 4 rows per step, :291-330). Empty → hint "Connect this location with the transport system…". **3D supplier/consumer flow arrows are only drawn while the corresponding collapsible is expanded** (industry.tl:329-361). Accordion → only one direction visible at a time.
- **Missing**: distance, "connected/which line serves it", inbound/outbound stations, link to station serving the industry.
- **Map context**: catchment area, industry HUD (towns/industries showing matching cargo in/out indicators), action tooltips filtered to relevant entities (entity_window_hud.tl:95-170).

### 1.7 Town building window
- **Recipe**: `TownBuildingWindow`, town_building/town_building.tl:252-508 (EP empty).
- **Status**: top row: building level, consumption rating per input cargo, residents icon (non-person-capacity), year built; input stocks (simplified); **Noise card** (rating bar; click → opens Noise layer `openLayerRidge`, :185-187); residents/workers card (`PersonCapacityWidget`; collapsible: `InhabitantsTable`); **Historic Preservation** checkbox (:200-228).
- **Actions**: Historic preservation toggle; noise → layer. No link to the parent town (needs verification whether title/HUD offers one; none in code).
- **Map context**: catchment area; town-building HUD (vehicles carrying to this town etc.).

### 1.8 Warehouse window
- **Recipe**: `WarehouseWindow`, warehouse/warehouse.tl; plugins warehouse_eow.script.tl.
- **Status**: Stocks card (`WarehouseCargoInfo`; "No Cargo Currently Stored"); Statistics chart (incoming/outgoing); maintenance bar.
- **Hidden actions**: collapsible of Stocks card (only if modifiable) = `EntityStockCountsWidget` with **Discard All Cargo** per stock (`makeStockListDiscardCargoCmd`) and **set stock cargo type** (via build proposal) (entity_window_util.tl:287-500, warehouse_eow.script.tl:126-140).
- **Actions**: Configure. Map: catchment (cargo only).

### 1.9 Maintenance station window (depot/maintenance building with maintenance pool)
- **Recipe**: `MaintenanceStationWindow`, maintenance_station/maintenance_station.tl.
- **Status**: Maintenance Pool progress (usage, "full" style), Balance, Statistics (max/avg usage), **Vehicles table** (sortable Vehicle, Condition) (maintenance_station_eow.script.tl:143-260); maintenance bar.
- **Actions**: **Manage Vehicles** (if it has depot nodes) → LVM with depot (closes EW unless pinned); Configure.
- Plain depots (no pool) open the LVM directly instead of a window (view_manager.tl:559-567).

### 1.10 Perk window (landmarks/HQ/special constructions via `entityWindowScript`)
- **Recipe**: `PerkWindowContent`, perk/perk.tl:20-227. Status: perk state/description (under construction text), production rules, stocks, booster/inhabitants, maintenance. Actions: **Configure**, **Show Company Window** (`openCompanyWindow`) (:115-135).

### 1.11 Resident (sim person) window
- **Recipe**: `SimPersonWindow`, sim_person/sim_person.tl; plugins sim_person_eow.script.tl.
- **Status**: 3D renderer + Enter Cockpit; **Locations** (Home/Shop/Work buttons → open those buildings, stacked, :97-157); **Happiness** bar (collapsible: happiness log by activity); **Current Route** (walk/car/line legs).
- **Actions**: destination buttons; horn; locate/follow.

### 1.12 Small windows
| Window | Recipe | Content / actions |
|---|---|---|
| Animal | animal/animal.tl, `AnimalStatePlugin` | movement state |
| Fun element (UFO etc.) | fun_elements/fun_elements.tl | state/speed |
| Empty construction | empty_construction/empty_construction.tl | notification + **Configure** |
| Bridge / Tunnel | bridge_and_tunnel.tl:43-251 | choose bridge/tunnel type, cost, "Not Enough Money"/errors, buy button (build proposal) |
| Double slip switch / Crossing | double_slip_switch.tl:628-680 | Yes/No combo → proposal |
| Traffic light (street node with >2 segments) | double_slip_switch.tl:15-626 | phases editor (add/remove phase, durations, allow skipping, min duration, set all to red, reset to default) |
| Rail crossing / Signal | make_entity_window.tl:278-291 | engine builtins `RailroadCrossingComp`, `SignalComp` (content not visible in Lua) |
| Mission / Subsidy | make_non_entity_window.tl | delegated to mission framework / subventions_gui |

### 1.13 Debug panel (brief)
- `debug_panel/make_entity_debug_panel.tl`: `EntityDebugPanel` (:242) generic component dump (`GenericView`), selectors to owning vehicle/station group/construction, stock editing, claim/forsake, add town EXP, remove component. Mounted only via engine `mountReactAdapterHost {type="EntityDebugPanel"}` (main/game.tl:207-213) – a developer/debug-mode surface, not part of the player UX.

---

## 2. Task flows

Counting: **C** = clicks, **W** = windows/screens involved, **CS** = context switches (a different window/tool takes over or the EW closes). Map clicks count as clicks.

### F1 "Why is this station overcrowded?"
1. Click station on map (1 C) → station window (or ConstructionWindow; if the station is not the first tab: +1 C on the tab).
2. At a glance: waiting-hall used/capacity + overflow icon; per terminal used/capacity (red when overflowing); per line stop: waiting passengers + unhappy count; terminal-too-short alert icon.
3. Hover each stop count to see destinations (hover, per row) / hover alert icons to read meaning.
4. To see whether the line has enough capacity: click LineStopButton (1 C, +1 W stacked) → line window shows rate + frequency (values on hover only).
5. Repeat step 4 for every line at the station (n C, n W).
- Total: **2 + n clicks, 1 + n windows**, several hovers. No aggregated "supply vs demand" per line, no cargo waiting at all.
- Fix (add capacity): see F5.

### F2 "What does this industry need and who supplies it?"
1. Click industry (1 C). Production card shows inputs/outputs and current production (no clicks).
2. Expand **Input Stocks** chevron (1 C) → suppliers table + 3D flow arrows (actual vs potential).
3. Sort by "Received" (1 C) to see who actually delivers.
4. Open a supplier (1 C, +1 W stacked) or locate it (1 C, camera).
5. To see consumers: expand Output Stocks (1 C) – collapses Input (accordion).
- Total: **2 C** for supplier list, **3–4 C** to inspect a supplier; consumer check +1 C. Distance/connection status not available → requires opening each supplier and/or using the cargo layer.

### F3 "Why is the town not growing?"
1. Click town (1 C). Town level card: growth level text + icon; progress percentage requires hover. Dashboard: 8 colour-coded ratings.
2. Click the worst-looking (by colour) rating (1 C) → detail page + chart + map layer.
3. Switch between ratings via the tab strip (1 C each, up to 7 more).
4. For Supplies: Statistics card → Suppliers toggle (1 C) → supplier table + flow arrows; open a supplier (1 C, stacked).
5. For Happiness/Delivery: line list → click line (1 C, stacked line window).
6. Back to overview: back tab or Esc (1).
- Total: **2 – 10 C** to scan causes; the reason "which single factor is the bottleneck" is not stated anywhere; ratings carry no numbers on the dashboard.

### F4 "Follow a vehicle and check its load"
1. Click the moving vehicle (1 C; hit-testing a moving target may need retries) – alternative: line window → vehicle table → name (2–3 C).
2. Load visible immediately in the load card (+ delivery-time/happiness %). Passenger list: expand (1 C).
3. Follow: title-bar Locate (1 C) → camera follows. Cockpit: 1 C (switches to FreeCam tool).
- Total: **2 C** (load + follow), **3 C** with passenger details.

### F5 "Jump from a vehicle to its line and add a vehicle"
Path A (official):
1. Click vehicle (1 C) → Basics card line button (1 C) → line window (stacked).
2. "Manage Line" (1 C) → LVM opens; **tool stack cleared → both EWs close** (unless pinned) (CS).
3. In the LVM: add vehicle (buy flow, see LVM inventory; ≥3–5 C).
- Total: **≥6 C, 3 screens, 1–2 CS**; to get back to the vehicle/line window: reopen from map (+1–2 C).
Path B (shortcut that exists but is hidden as an icon): vehicle window → **Clone** icon (1 C) → buys an identical vehicle; line assignment by `findBestLineAndDepotForVehicle` (needs in-game verification). Total **2 C**, no CS.
Path C: from line window there is **no** "add vehicle" button; user must open a vehicle from the table (1 C) then Clone (1 C) → 3 C from line window.

### F6 "Send a vehicle to depot / sell / replace / change its line"
- Depot: vehicle → Send to Depot icon: **2 C** (icon-only, hover to identify).
- Sell: **2 C**, no confirmation.
- Replace: vehicle → Replace toggle (2 C) → Vehicle Store window (further selection; EW stays open).
- Change line: vehicle → Send to Line (2 C) → LVM in send-to-line mode (CS, EW closes unless pinned) → choose line (≥1 C).
- Per-vehicle only; bulk requires the LVM.

### F7 "Find and replace old vehicles on a line"
Line window → sort Vehicles table by Age (1 C) → click vehicle (1 C) → Replace (1 C) → store window flow → repeat per vehicle. **≈3 C + store flow per vehicle**; no bulk select in the EW.

### F8 "Is this line profitable?"
Click a vehicle/station → open line (2 C) → scroll to Balance chart (order 60, bottom; scroll). Only a chart, no current-year profit number as text. Transported "Last Year" number is visible.

### F9 "Compare two stations / lines side by side"
Open first (1 C) → pin it (1 C) or drag window → click second (1 C). Without pinning the first window closes. Gamepad: cannot pin, but stacks automatically.

### F10 "Rebuild / upgrade a station or industry"
Station/industry/warehouse/depot window → Configure (1 C) → construction menu module builder (stacked tool). **2 C**.

### F11 "Check a warehouse and discard stuck cargo"
Click warehouse (1 C) → expand Stocks (1 C) → Discard icon (1 C). **3 C**.

### F12 "Where do residents of this building go / why unhappy"
Click building (1 C) → expand residents (1 C) → InhabitantsTable → click resident (1 C, stacked) → Locations/Happiness/Route. **3 C**.

### F13 "Close everything"
Delete key (uiCloseAll) or Esc per window; pinned windows survive map clicks but not uiCloseAll (engine `closeAllWindows`).

---

## 3. Friction findings

| # | Finding | Evidence | Impact |
|---|---|---|---|
| 1 | **Mouse map click closes all other unpinned windows**; stacking only via in-window links or pin/drag. Comparing entities needs an extra pin step; pin not available on gamepad. No modifier (e.g. Shift) for stacking. | selector_react_util.tl:108 (`stack = allowStacking==nil and isGamepad`); view_manager.tl:581-584, 525-554, 312 | High |
| 2 | **Opening the LVM from an EW ("Manage Line", "Send to Line", "Manage Vehicles") closes the EW itself** (tool stack cleared) – user loses context and must re-navigate. | line.tl:143-148; vehicle.tl:399-405; maintenance_station.tl:87-93; manager_window.tl:8474 `push(ManagerTool, nil, …)` without allowStacking; builtin.lua:1383-1389 | High |
| 3 | **Line window has no stop/station list, no per-stop waiting counts, no load factor and no "add vehicle"** – the most frequent line tasks require the LVM. | line_eow.script.tl plugin set (lines 26-690); line.tl:137-161 | High |
| 4 | **Station window ignores cargo**: waiting counts per stop use only the passenger cargo type; capacity bars only for `isStationOfType(…,false)`; destinations only on hover. | station_group.tl:641-646, 704-710, 648-691 | High |
| 5 | **Supply chain is hidden behind a collapsible**, map flow arrows only while expanded, accordion prevents seeing inputs & outputs together; tables lack distance / served-by-line / connected state, and list every matching industry on the map (noise). | industry.tl:329-361; industry_eow.script.tl:280-398, 768-796; industry_util.tl:603-649; content_card.tl:457-470 | High |
| 6 | **Town growth diagnosis needs up to 8 tab clicks**; dashboard shows only colour-coded levels, no numbers, no "main blocker"; progress % only in tooltip. Esc first goes back to overview, second Esc closes. | town.tl:671-743, 759-833, 1281-1287; town_eow.script.tl:85-95; town_react_util.tl:2225-2278 | Med-High |
| 7 | **Secondary actions are icon-only** (Reverse, Start/Stop, Clone, Replace, Modify, Depot, Sell) → hover needed; the useful "Clone = add vehicle to this line" is undiscoverable. | entity_window_util.tl:1116-1185 (tooltip only when not primary) | Med |
| 8 | **Sell has no confirmation** (irreversible, 1 mis-click). | vehicle.tl:524-536 | Med (risk) |
| 9 | **Accordion collapsibles + state reset on reopen** – expanded sections (e.g. suppliers, passengers) must be re-expanded every time; two sections cannot be open together. | `makeContentCardsCollapsibleFunctions(…, true)` in vehicle.tl:231, line.tl:120, station_group.tl:848, town.tl:1230ff, industry.tl:283, warehouse.tl, town_building.tl:325 | Med |
| 10 | **Line vehicle table is minimal** (Vehicle, Age): no condition, load, profit, state (stuck/in depot), no multi-select or bulk action. | line_eow.script.tl:236-247 | Med |
| 11 | **Missing cross-links**: station → towns/industries in catchment; town building → its town; station → vehicles currently there; line → its stations; vehicle → full stop list. Navigation is one-directional and windows just pile up (no back/history/breadcrumb). | station_group.tl (only LineStopButton), town_building.tl (no selectEntity), line_eow.script.tl | Med |
| 12 | **Depot click opens the full LVM** instead of a light window – heavy context switch for a "what's in this depot" glance. | view_manager.tl:559-567 | Med |
| 13 | Status values (line rate, frequency, speed, progress to next town level, destinations) **only in tooltips**. | line_eow.script.tl:34-78; station_group.tl:95; town_eow.script.tl:88-95 | Med |
| 14 | Important cards at the bottom of a fixed-height scroll area (e.g. line Balance order 60, vehicle Balance order 70) → scrolling needed. | entity_window_sizes.lua:3-4; .res.lua orders | Low |
| 15 | ConstructionWindow tabs show only type names ("Train Station", "Depot"), no names/status/warnings; station may not be the first tab. | make_entity_window.tl:46-102, 220-252 | Low-Med |
| 16 | All info callouts disabled (texts ""), no in-window help. | content_card.tl:70-75; all `--_("CALLOUT_…")` | Low |
| 17 | Only the active window's map overlay is shown; with several windows open the map context jumps with focus. | view_manager.tl:122-142, 299-305 | Low |
| 18 | Gamepad: no pinning; all windows stack until closed individually. | view_manager.tl:312, 528 | Low (mouse focus) |

---

## 4. Improvement opportunities

Feasibility legend: **Easy** = new react-plugin into an existing extension point (res file + recipe); **Medium** = `GloballyReplaceRecipeBeforeInitInternal` of a registered recipe (optionally calling `CallOriginalRecipe`); **Hard** = needs monkey-patching of non-recipe module functions (needs verification) ; **Not feasible** = engine change.

| # | Proposal | Saving | Moddability |
|---|---|---|---|
| I1 | **Line "Stops" card**: list all stops in order with station name button (stack), waiting passengers **and cargo** per stop (`getCargoQualityDataAtStop(line, stop, cargoType)`, `getLineStopSimEntities`), unhappy count, overlength alert, plus load factor of the line's vehicles. | F1 from line side: n window opens → 0; line → station: 1 C instead of map hunting | **Easy** – new plugin on `LineEowExtensionPoint` (order ~25); APIs used already in station_group.tl:664, 705, 712 |
| I2 | **"+1 vehicle" / "−1 vehicle" buttons in the line window** (clone the newest line vehicle via `duplicateVehicles` event, or sell oldest). | F5: ≥6 C + CS → **1 C**, no CS | **Easy** as a plugin card (buttons inside a card; action bar itself not extensible). Event `duplicateVehicles` handled in manager_window.tl:8493 (requires LVM entry recipe mounted – it is, it's global) |
| I3 | **Keep EWs open when opening the LVM** (push ManagerTool with `allowStacking=true`, or auto-pin the source EW before firing `openVehicleManager`). | Saves re-navigation (2–3 C) after every LVM visit | **Medium**: replace `LineWindowContent`/`VehicleWindow`/`MaintenanceStationWindow` (auto-pin needs access to EW pin state → simpler: replace the LVM entry recipe that handles `openVehicleManager`, manager_window.tl:8447, to push with stacking). Verify tool-stack side effects in-game |
| I4 | **Shift/Ctrl-click to stack** (or "always stack, max N windows, oldest unpinned closes"). | F9: 3 C → 2 C; no pin needed | **Medium**: replace registered `ViewManager` recipe (view_manager.tl:524) and override `stack` handling; modifier-key state from `api.util`/input (needs verification). Changing the selector's `stack` default (selector_react_util.tl:108) is **Hard** (plain function) |
| I5 | **Station "Overview" card** in the empty station extension point: per line served – frequency, rate, waiting pax+cargo, load of arriving vehicles; cargo waiting per cargo type; inline destination breakdown (no hover); towns/industries in catchment as buttons. | F1: 2+n C + hovers → **1 C** | **Easy** – plugin on `StationGroupEowExtensionPoint` (station_group.tl:864, currently empty) |
| I6 | **Industry "Supply summary" card** (order 5): per input/output cargo – received/supplied last period, number of connected vs potential partners, nearest unconnected partner (distance), quick buttons to partner windows; optionally always-on flow arrows. | F2: 2–4 C → **1 C** | Card: **Easy** (plugin on `IndustryEowExtensionPoint`). Always-on arrows: **Medium** (layer config built inside `IndustryWindow`, industry.tl:329-361 → replace recipe) |
| I7 | **Town "Growth blockers" card** (order 15): the 8 ratings sorted worst-first with numeric value/label and one-line reason, plus progress % as text; supplies deficits per cargo. | F3: 2–10 C → **1 C** | **Easy** – plugin on `TownEowExtensionPoint`, data via the same parallel functions (`getRatingFnName` in `GetRatingsDashboard`, town_react_util.tl:2150-2205). Jumping into a rating tab from the plugin is not possible (tab state is internal to `TownInformationWidget`) → render details inline or **Medium** replace `TownInformationWidget` |
| I8 | **Labelled action bar / richer vehicle quick-actions card**: show text labels for Clone/Depot/Replace, add "Open line", "Next stops", "Follow" buttons, confirmation for Sell. | Removes hover-to-identify (≈1 hover per action); prevents mis-sell | Extra card with labelled buttons: **Easy** (plugin on `VehicleEowExtensionPoint`). Changing the existing bar/confirm on Sell: **Medium** (replace `VehicleWindow` or `ActionButtonBar` recipe, entity_window_util.tl:1187) |
| I9 | **Non-accordion, persistent collapsibles** (remember expanded cards per window type across reopen). | Saves 1 C per reopen per section (suppliers, passengers…) | **Medium**: replace each window recipe, or **Hard** monkey-patch `content_card.makeContentCardsCollapsibleFunctions` (needs verification) |
| I10 | **Rich line vehicle table** (condition, load %, state, profit, age) with multi-select + bulk Replace/Depot/Sell. | F7: ≈3 C/vehicle → ≈3 C total | **Medium**: replace registered plugin recipe `LineVehiclesPlugin` (line_eow.script.tl:640) or add new plugin + override `line_eow_vehicles.res.lua` (override-by-path: needs verification). Bulk commands exist (`makeVehicleSellCmd({…})` takes a list, vehicle.tl:361) |
| I11 | **Cross-link cards**: town building → town button; station → catchment towns/industries; vehicle → full stop list with ETA. | 1–3 C per navigation, avoids map hunting | **Easy**: plugins on `TownBuildingEowExtensionPoint` (empty), `StationGroupEowExtensionPoint`, `VehicleEowExtensionPoint` |
| I12 | **Back/forward history & breadcrumb** for window navigation (vehicle → line → station → town), optionally replacing content in-place instead of piling windows. | Avoids window clutter, 1 C to return | **Medium–Hard**: replace `ViewManager` (history of `selectEntity`) and `EntityWindow` wrapper (view_manager.tl:94) for a back button; title-bar buttons are engine `builtin.Window` → custom button must go into content |
| I13 | **Light depot window** (vehicles in depot, buy, send all to line) instead of auto-LVM. | Glance: LVM (heavy) → small window | **Medium**: replace `ViewManager` (depot branch view_manager.tl:559-567) and provide content via `make_entity_window` (Hard) or via a custom `entityWindowScript` on depot constructions (data-driven, **Easy-Medium**; construction desc change → needs verification for base depots) |
| I14 | **Status in ConstructionWindow tabs** (name + warning dot). | Saves blind tab switching | **Medium**: replace `ConstructionWindow` recipe (make_entity_window.tl:117) |
| I15 | Surface tooltip-only values as text (rate, frequency, % to next level). | Removes hovers | **Medium** (replace `LineRate`/`LineFrequency`/`TownLevelWidget` recipes – all registered) |

Notes / needs in-game verification:
- Where stacked windows are placed on screen and whether they overlap (`initialX=1, initialY=0`).
- Whether Clone assigns the copy to the same line (`findBestLineAndDepotForVehicle`).
- Whether pinned windows survive `uiCloseAll` (engine `api.gui.closeAllWindows`).
- Semantics of `isStationOfType(station, false)` (capacity bars for cargo stations).
- Whether a mod can override base `.res.lua` plugin registrations by path (to remove/replace default cards without `GloballyReplaceRecipe`).
