# 05: Statistics, finances overview, menus (pause/main/save/load/settings), map editor

Scope: `gui/gui/statistics/*`, finance window (`game_mechanics/game_mechanics/finance/*`, included here because it is the only other "overview" surface), `gui/gui/main/pause_menu.tl`, `gui/gui/menu/*`, `gui/gui/map_editor/*` (surface list only).
Paths below are relative to `SCR/game/` (SCR = scratchpad). `stat/` = `gui/gui/statistics/`, `menu/` = `gui/gui/menu/`, `fin/` = `game_mechanics/game_mechanics/finance/`.

## 1. Surfaces

### 1.1 Statistics window (shell)

StatisticsWindow / StatisticsContainer (`stat/statistics.tl:643`, `:201`). One window with 7 tabs, each a sortable DataTable. Title "Statistics", `movable = false`, `compact = true`, `closable = true` (`statistics.tl:647-657`). Registered as the variant tool "Statistics" (`statistics.tl:668`, `registerVariantToolWithWindow`). It sits on the tool stack: opening another tool hides it ("shelves" it), and it comes back when that tool is popped (`main/tool_react_util.tl` `shelve`).

- Tabs, in order (`statistics.tl:187-199`): Lines, Vehicles, Stations, Warehouses, Depots, Towns, Industries. Which tabs are enabled is set in `main/game.tl:255-263`. The map editor shows only Town and Industry.
- Entry points:
  - Game-bar right: 7 separate `StatisticsToolButton`s, one per tab (`game_bar/game_bar.tl:1129-1192`). Each is a ToolButton whose `showFn` fires `openStatisticsWindow(tabKey)` and whose `hideFn` fires `closeStatisticsWindow` (`game_bar.tl:1085-1110`). Clicking the button of the active tab closes the window.
  - Hotkeys `IA_SELECT_STATISTICS_LINES / _VEHICLES / _STATIONS / _TOWNS / _INDUSTRIES / _WAREHOUSES / _DEPOTS` (`main/game.tl:267-275`, forwarded at `game.tl:824-830`, also bound in `game_bar.tl:1197`). Inside the open window, the same hotkey closes it if that tab is already active and switches tab otherwise (`statistics.tl:236-245`). The default key assignments are engine-side and need in-game verification. Key mapping category "statistics" exists in settings (`menu/settings_page.tl:95`).
  - Radial menu (gamepad) entry "Statistics". It always opens the first enabled tab, i.e. Lines (`game_bar.tl:92-102`).
  - The event `openStatisticsWindow` is fired only from the game bar. No entity window links into the statistics window (grep).
- Close: X button, a second press of the active tab hotkey or button, `closeStatisticsWindow`.
- Shared header (`statistics.tl:576-638`), floating top-right:
  - Carrier category toggle buttons: Road, Tram, Rail, Water, Air. Only Lines, Vehicles, Stations and Depots have them (`statistics_react_util.tl:122-165`).
  - An eye toggle, "Show Only Visible {object}", which limits the list to entities on screen (`statistics_react_util.tl:43-77`).
  - A search field (`createSearchField`, `:167`) that filters on every keystroke (`onTyping`).
  - An Expand/Shrink toggle (`statistics.tl:586-600`).
  - The tab widget itself (`statistics.tl:611`).
- Persistence: per-tab filter state (categories, onlyVisible, search, sort column) is stored in a `react.useRef` inside `StatisticsEntryPoint` (`statistics.tl:673-688`). It survives closing and reopening the window. It is not saved with the savegame and is most likely lost on load (needs in-game verification).
- Map overlay while the window is open (`setActionFn`, `statistics.tl:279-468`):
  - Lines/Vehicles: `LineViewer` draws the lines. On the Lines tab it draws only the lines that pass the current filter and search (`getVisualizeLines` API, `statistic_lines.tl:427-434`, `statistics.tl:292-336`).
  - Towns: voronoi town areas.
  - Stations: passenger and cargo catchment.
  - Depots: maintenance catchment.
  - HUD icons are restricted to the tab's component types (`statistics.tl:45-51`). Through `HudIconManagerStatistics` (`:59-156`, 0.5 s step timer) they show notification icons plus a cargo in/out indicator for stock lists and warehouses.
  - Hover tooltip `DefaultEntityToolTip`, filtered by carrier (`:448-454`). Clicking the map selects the entity (`makeDefaultSelectorIfMouse`).
- Code facts:
  - The window has no `ExtensionPoint` or `usePlugins` anywhere (grep).
  - Each tab is a module whose return value is the tab recipe (e.g. `statistic_lines.tl:465`). Each tab can therefore be replaced as a whole through `react-replacement-config` → `ReplaceRecipe` (`main/bootstrap_game.tl:6-49`). `StatisticsContainer` and `StatisticsWindow` are module-local; only `statistics.StatisticsEntryPoint` is exported.
  - All cell recipes are local. Adding or changing a column means replacing the whole tab recipe.
  - Cells refresh through `useStepStateTimer` (default 0.5 s, `main/engine_react_util.tl:126-141`). Row keys refresh every step (`useStepState`).
  - The table is `builtin.DataTable` (`scripts/scripts/builtin.d.tl:1160-1185`). It supports `fnUserFilter`, per-column `getCompareValue` and `initialSortColumn`, and has `iaSort = IA_OPTION1`. It has no multi-select, column hide/reorder, aggregate footer or row-click callback.

### 1.2 Lines tab: `LinesStatistic` (`stat/statistic_lines.tl:299`)
- Rows: `lineSystem.getLinesForPlayer` (`:380`).
- Filter: carrier categories (`:301-307`), onlyVisible (`isLineEmptyOrVisible`). Search matches the line name or any cargo name (`:309-342`).
- Columns (`:403-415`):

| # | Column | Content | Sort key |
|---|---|---|---|
| 1 | Name | Colour swatch, locate button, line name (opens the line window, stacked), pencil rename (`LineLocationAndNameCell` :17, `NameTextView` `line_vehicle_mgmt/line_react_util.tl:310-380`) | name |
| 2 | (alert icon) Problems | The first "Problem" notification icon plus a count. Tooltip is the title, or "There Are Several Problems". Click runs the notification's `onClick` (`statistics_react_util.tl:317-369`) | count, then ids |
| 3 | Vehicles | `VehicleWidget` icon strip. Click fires `openVehicleManager{openWithLineEntity}` (`:36-57`) | list of model ids, not the count (`:262-275`) |
| 4 | Cargo | Cargo icons | cargo info |
| 5 | Load | Current load of all vehicles | |
| 6 | Capacity | | |
| 7 | Utilization | Load/capacity in % | |
| 8 | Satisfaction | Average quality in % | |
| 9 | Frequency | mm:ss (`line_util.calculateFrequencySeconds`) | |
| 10 | Rate | Annual throughput (`calcLineStationThroughput`) | |
| 11 | Balance | Rolling 12-month balance, red/green (`LineBalance`, `line_react_util.tl:621-640`) | see F-S7 |

- No row actions besides rename, locate, open and the vehicles link.

### 1.3 Vehicles tab: `VehiclesStatistic` (`stat/statistic_vehicles.tl:316`)
- Rows: all `TRANSPORT_VEHICLE`s owned by the player (`:322`).
- Filter: carrier, onlyVisible (`isVehicleVisible`). Search matches the vehicle name, line/instruction name, cargo name or condition label (`:418-468`).
- Columns (`:358-371`):
  - Name: locate, open (stacked), rename.
  - Problems.
  - Vehicle: model image, click opens the vehicle window (`selectEntity`, stack).
  - Line: instruction icon plus line name. The line name is a `NameTextView` that opens the line window.
  - Cargo, Load, Capacity, Utilization, Satisfaction.
  - Condition: text label (`vehicle_util.getConditionText`).
  - Age.
  - Balance: 12-month balance.
- Missing: no "send to depot", "replace", "sell", multi-select or "old/unprofitable" flag.

### 1.4 Stations tab: `StationsStatistic` (`stat/statistic_stations.tl:250`)
- Rows: station groups owned by the player or by nobody, only if at least one line uses them (`:256-264`).
- Columns (`:271-280`):
  - Name: locate, open, rename.
  - Problems.
  - Town: link to the town (`:43-57`).
  - Lines: the count only, not clickable.
  - Type: Cargo / Passenger / Mixed.
  - Utilization: used/capacity, including the waiting hall.
  - Delay: count of unhappy passengers with an "Aloof" emote. This is passenger-only (`calculateQualityInfo`, `:160-162`).
  - Upkeep.
- Filter: carrier, onlyVisible. Search matches the station, town or type label.

### 1.5 Warehouses tab: `WarehousesStatistic` (`stat/statistic_warehouses.tl:302`)
- Rows: all `WAREHOUSE` entities. There is no player-ownership filter (`:308`).
- Columns (`:320-328`): Name, Problems, Stocks (cargo icons, or "All Cargo Types"), Stored, Capacity, Utilization, Upkeep.
- Filter: no carrier filter (`declareFilterOnMount({}, ...)`, `:332`), onlyVisible. Search matches the name or a cargo. The literal English word "empty" matches empty warehouses (`:381`, not localized).

### 1.6 Depots tab: `DepotsStatistic` (`stat/statistic_depots.tl:161`)
- Rows: all `VEHICLE_DEPOT` entities, with no owner filter (`:174`).
- Columns (`:162-168`):
  - Name.
  - Parked: vehicle strip. Click → `openVehicleManager{openWithDepotEntity}`.
  - Maintained: vehicle strip. Click opens the manager without context, because `nil` is passed (`:57-68`).
  - Usage: maintained / pool size.
  - Upkeep.
- No Problems column.
- Filter: carrier (checked against the depot's transport modes), onlyVisible, search on the name.

### 1.7 Towns tab: `TownsStatistic` (`stat/statistic_towns.tl:462`)
- Rows: all towns.
- Columns (`:496-513`):
  - Name.
  - Problems.
  - Size (level name).
  - Population: residential capacity (icon header).
  - Public Transport %, Private Transport % (icon headers).
  - Cargo, Supply, Demand, Coverage.
  - Six rating bars with icon-only headers: urban care, traffic, happiness, cargo delivery, noise, pollution.
- Filter: onlyVisible only. Search matches the name, a cargo or the reputation label.

### 1.8 Industries tab: `IndustriesStatistic` (`stat/statistic_industries.tl:386`)
- Rows: all industries.
- Columns (`:404-415`):
  - Name.
  - Problems.
  - Requirements: input cargo icons.
  - Product: output icons.
  - Input /yr, Output /yr.
  - Workload %.
  - Boosters.
  - Workplaces: occupied/capacity.
  - Shipment: annual shipped amount.
- Filter: onlyVisible. Search matches the name, input, output or booster cargo.

### 1.9 Finance window (overview information outside the statistics window)

FinancesWindow / FinanceAccount (`fin/account.tl:131`, `:13`). The window title is the editable company name (`:140-146`). Tool "Finances" (`:162`).

- Entry: the "Account" money display in the game bar (`game_bar/game_bar.tl:296-326`, ToolButton toggle) or the radial menu "Finances" (`game_bar.tl:104-112`). Event `openFinanceWindow(tabKey)` (`main/game.tl:289-301`). I found no `IA_` hotkey for it (grep).
- Tabs (`account.tl:52-124`):
  - Overview (`finances_charts.tl:409-488`): four charts. "Revenue and Expenses" and "Debt and Cash" have a year slider (4–N years, default 20, `:25-183`). The other two are "Balance" (bank account vs company value) and "Towns" (residential, commercial, industrial).
  - Finances (`finances_table.tl:563-710`): earnings table for the current year plus 3 previous years (`config.count = 4`, `:572`). Rows can expand per carrier (Road, Rail, Tram, Water, Air, Other), plus Investments, Loans and a summary (Earnings, Bank Account, Debt).
  - Assets (`finances_assets.tl`): cards for vehicles, infrastructure lengths, stations by type, "bests" (supplied towns, connected industries, number of lines, top speed, longest train, oldest vehicle) and a cargo chart.
  - Loans.
  - Delivery Time (`finances_cargo_lifetime.tl`): expected delivery time per cargo type.
- Not available anywhere:
  - Per-line or per-vehicle financial history. The only per-line or per-vehicle money figure is the rolling 12-month "Balance" number in the statistics tables.
  - Revenue/cost split per line.
  - Profit per carrier over time as a chart.
  - Totals for lines or vehicles.

### 1.10 Pause menu (in-game escape menu)

PauseMenu (`main/pause_menu.tl:408`), a full-screen window. Tool `PauseMenuTool` (`:428-437`). It pauses the game through `setInGameMenuPause(true)` (`:263-268`).

- Entry: `IA_MENU` (`main/game.tl:803` forwards it to the game UI; default key presumably Esc, needs verification) or the game-bar burger button `menu.fileMenu` (`game_bar.tl:1195-1211`). Event `openPauseMenu` (`game.tl:195-205`).
- Close: `IA_MENU` again, `IA_MENU_BACK`, Resume.
- Top bar: a wall clock and "Game Paused – {savegameName}" (`:376-400`).
- Buttons (`PauseMainPage`, `:57-234`):
  - Resume.
  - (Map editor only) Save and Play.
  - Save Game / Save Map → `SaveGamePage`.
  - Load Game / Load Map → `LoadGamePage` with `inPauseMenu = true`.
  - Settings → `SettingsPage`.
  - Quit. This toggles a sub-rack with "Return to Main Menu" (`app.stopGame()`) and "Return to Desktop" (`app.quit(true)`). On PC neither asks for confirmation. The "unsaved progress will be lost" dialog is used only on console (`:160-213`, `quitWithConfirmation` `:15-45`).
- Save, Load and Quit are disabled while a save is in progress (`isSavegameUIBlocked`, `:61-63`).
- Page state: `Main | SaveGame | LoadGame | Settings | ModManager` (`:344-355`). ModManager has no button on the main page; it is reachable only through load/mod-selector flows.
- Code facts: `PauseMainPage`, `PauseMenuContent` and `PauseMenu` are all local, so they cannot be replaced individually. Only the page modules (`SaveGamePage`, `LoadGamePage`, `SettingsPage`, `ModManagerPage`) are replaceable recipes.

### 1.11 Quicksave
- Code: `IA_QUICKSAVE` (`main/game.tl:790-796`) saves to `api.gui.game.getDefaultSavegameId()` (the current save name) with `skipSetName = true`, without confirmation. The only feedback in Lua is `log.verbose`. Whether the engine shows a toast needs in-game verification. The tip string is `TIP_MISC_6` (`strings_en.tsv:2590`).
- Gap: there is no quick-load action anywhere (grep "quickload" finds nothing).

### 1.12 Save page: `SaveGamePage` (`menu/save_game_page.tl:154`)
- Layout: a tile list, 5 columns. The first tile is the "Add New" `SaveCard`: a name field pre-filled with the current save name (`:157-158`), with characters `./\=+:*?"<>|` blocked (`:107-109`), and a Save button.
- Other tiles: existing manual save groups only (`SaveGameType.Manual` filter, `:163`). Saves are grouped by name through `app.parseSavegameName`.
- Header: filter text field plus sort (Name / Date) (`savegame_react_util.tl:703-740`).
- Click on a group tile: the name is copied into the field. On gamepad this asks to overwrite directly.
- Double-click on a tile: overwrite confirmation (`:225-238`).
- Name collision: saving under an existing name opens the "Overwrite Savegame" dialog (`:27-57`, `:70-88`).
- After saving: the whole pause menu closes (`commonParams.onClose()`, `:206`).
- Console only: storage bar.

### 1.13 Load page: `LoadGamePage` (`menu/load_game_page.tl:22`)
- Layout: a tile list of save groups (manual, auto, crash and exit saves together) plus built-in savegames. Filter and sort as on the save page.
- Each card (`SavegameCard`, `savegame_react_util.tl:244-490`) shows:
  - a screenshot;
  - an error badge for missing mods, unsupported size or a load failure (`checkForError` `:220-241`);
  - a primary "Load Game" button that loads the group's most recent manual save.
- In-game load happens immediately via `app.loadGame`, without a "unsaved progress will be lost" confirmation (`:340-345`, `:1150-1153`).
- Details (`SavegameSelectCard`, `:848-1500`):
  - a list of the saves in the group, with columns Type, Year, Mods, Size, Date Saved (`:1311-1335`);
  - the description (date, population, rank, stations, lines, vehicles, account, `:494-610`);
  - Delete with a confirm dialog (`IA_OPTION2`, `:1171-1225`);
  - Share/Update to the mod hub;
  - "Gameplay Settings" and "Mods (n)" sub-pages (`:1390-1435`, mod selector `:1477`).

### 1.14 Settings page: `SettingsPage` (`menu/settings_page.tl:1374`)
The same page is used from the main menu and the pause menu (`inGame` flag). Changes apply immediately (`applyChanges`, `:1403-1432`). Buttons: "Reset to Default" and "Revert Changes" (`:1511-1530`). "Restart Required" notice (`:2196`). Restart-requiring options trigger a restart only from the main menu (`:1463`). Some options are disabled in game (`disabledInGame`, `:1847` etc.), for example Language (`:384`).

Tabs and groups (`makeTabs`, `:351-1370`):

| Tab | Groups and options |
|---|---|
| Interface | Basics: Language. Interface Scaling: Text Scaling, Game UI Scaling (`:390-415`). Localization: money format and units. HUD: Prevent Overlapping Icons, Rain Screen Effect, Cloud Transparency. Misc: Enable Celebrations. ("Enable Interactive Guides" is commented out, `:519`.) |
| Mouse | Invert pan/rotate/tilt/zoom, zoom to/from cursor, continuous zoom, panning mode, edge scrolling, wheel sensitivity, Back With Right-Click, movement sensitivity (`:541-626`) |
| Keyboard | Invert rotation keys, camera speed. Key Mapping: per-action rebinding grouped by category (General, Game, Campaign, Statistics, Layers, Construction, Camera, Camera Tool, `:91-100`), with a search field (`:1650-1700`), a conflict dialog "Overwrite Existing Key Binding" (`:162`) and a per-row reset (`KeyBindingsEntry`, `:316-348`). The list of actions comes from the engine's input-action descriptors (`desc.uiCategory/uiName/uiOrder`). |
| Gamepad / Controller | Invert options, dead zone and sensitivities (`:680-765`) |
| Graphics | Display mode, resolution, scale, VSync, presets and individual quality options (`:829-996`) |
| Audio | Music on/off, menu music, voice-over, playlist, volumes, bulldoze/construct SFX (`:1061-1178`) |
| Advanced | Background contrast layer, Drag-and-Confirm construction, Advanced Camera Tool, GUI effects, Autosave Interval (Off/1/2/5/10/15/30/60 min), Autosaves To Keep, system cursor, debug options, Open User Data Folder (`:1187-1320`) |

- No notification settings exist (grep "otification" in `settings_page.tl` finds nothing).
- No camera bookmarks or statistics-column preferences.

### 1.15 Main menu: `MainMenu` (`menu/main_menu.tl:499`)
- Pages: the `Page` enum in `menu/main_menu.d.tl:3-22`, page switch at `main_menu.tl:854-892`.
- Main page (`menu/main_page.tl:129`):
  - Continue: loads the last save in one click, unless it is broken (`:316-500`).
  - Campaign, New Game, Load Game, Mod Hub, Map Editor, Quickstart Tutorial (`:557-700`).
  - Release notes, Achievements, Settings, Credits, Quit Game (`:510-545`).
- New Game (`new_game_page.tl:14`) → `NewGameOrMapSettingsPage` (`new_game_or_map_settings_page.tl:448`):
  - World, Terrain, Civilization and Environment groups.
  - Map size/format, names, economy, start year.
  - "Gameplay Settings" → `GameplaySettingsPage` (`advanced_settings.tl:26`): Difficulty, Economy, Town Ratings, Finances, Advanced, Experimental.
  - Mods → `ModSelectorPage`.
  - "Start Game" → `ProgressPage` (loading screen, `progress_page.tl:7`).
- Campaign (`campaign_page.tl:60`): campaign list → mission details (`mission_page_content.tl:378`: characters, objective, star requirements, special award, Start/Continue/Restart).
- Tutorial page (`tutorial_page.tl`), Achievements (`achievements_page.tl`), Credits, License, Release notes window.

### 1.16 Mod Hub and mod selector (brief)
- ModManagerPage (`menu/mod_manager_page.tl:14`, backed by `mod_manager_react_util.tl`, 6030 lines): browser tabs per backend, author pages, a restricted mod-management mode inside the pause menu (`main/pause_menu.tl:294-302`).
- ModSelectorPage (`menu/mod_selector_page.tl:682`), used from New Game and from the Load details:
  - optional DataTable view (`:690`, `:1505`);
  - actions per row: configure, move top/up/down/bottom (`:463-536`);
  - missing-mods panel with Show All, Deactivate All and Subscribe All Possible (`:244-320`);
  - presets save/load (`:590-660`);
  - confirm dialogs for dependencies, conflicts, memory budget and circular dependencies (`:871-1290`).

### 1.17 Map editor (surface list only): `map_editor/map_editor.tl`
`MapEditorTool` is a variant tool with persistent windows (`:2908`). The variants are `map-editor-generate-heightmap | -import-heightmap | -generate-townsIndustries | -generate-street` (`map_editor.d.tl:5-10`). Surfaces:
- `MapEditorContainer` (`:2709`): Generate / Import / Export sections for Heightmap, Biomes, Towns, Industries, Main Connections (`:2729-2864`).
- `GenerateHeightmapSettings` (`:541`).
- `ImportExportHeightmapSettings` (`:858`).
- `ImportBiomesSettings` (`:1174`).
- `ImportExportTownsIndustriesSettings` (`:1661`).
- `TownsIndustriesSettings` (`:2073`).
- `MainConnectionsSettings` (`:2406`): auto-detect, propose default connections, clear.
- `FileListContainer` / `FileSelector` (`:31`, `:141`).
- `Preview` (`:2644`).

`IA_OPTION1` triggers Generate/Import in each panel. The map editor pause menu adds "Save and Play". Statistics in the map editor are limited to Towns and Industries.

## 2. Task flows

Click counts assume mouse. Each "→" is one click unless noted.

T1. Find unprofitable lines. Game-bar "Line Statistics" (or its hotkey) → click the "Balance" header (one or two clicks for ascending order). That is 2–3 clicks, 1 screen. The figure is the rolling last 12 months only. Neither this window nor the finance window offers a trend per line.

T2. Find why line X is unprofitable.
1. T1 (2–3 clicks).
2. Read Utilization, Satisfaction, Frequency and Rate in the row.
3. Click the line name → line window (stacked; the statistics window is shelved). The cause has to be found there; see the line inventory.
4. Close → the statistics window returns.

That is at least 4 clicks and 2 context switches. There is no breakdown of revenue against running and maintenance cost per line in any surface.

T3. Add or remove vehicles on a line, starting from statistics. Line Statistics → click the vehicle strip in the "Vehicles" cell → vehicle manager opened on that line (`statistic_lines.tl:46-53`) → act there. That is 2 clicks to reach the manager. There is no "+1 vehicle" inline.

T4. Find old or badly maintained vehicles to replace. Vehicle Statistics → sort by "Age" or "Condition" (one or two clicks) → for each vehicle, click its image to open the vehicle window → replace or sell there → close → next vehicle. That is 3–4 clicks per vehicle and N context switches. There is no multi-select, bulk replace or bulk "send to depot". Search matches the condition label, so typing the label narrows the list.

T5. See all problems or warnings in one place. Each tab has a Problems column sortable by count. You have to visit up to 6 tabs, because the Depots tab has none. In a row, only the first problem's icon and title are shown; the rest is summarised as "There Are Several Problems" (tooltip) (`statistics_react_util.tl:327`). Click it → the notification action.

T6. Find stations with overcrowding or delays. Station Statistics → sort Utilization or Delay. This gives 2–3 clicks. Delay counts passengers only, so cargo delays are not visible here.

T7. Find a station without lines that still costs upkeep. Not possible in Station Statistics, because such stations are filtered out (`statistic_stations.tl:259-263`). You have to look in the Finances → Assets counts or find it on the map.

T8. Check whether an industry chain is starving. Industry Statistics → sort Workload, or search a cargo name → compare Input and Output. Locate a row → camera jump. That is 2–4 clicks.

T9. Check the company-wide finances. Click the Account display → Overview charts (1 click). Finances tab: +1 click, and expanding a carrier is +1 click per carrier. Years shown are fixed at 4 in the table; the charts have a slider.

T10. Save under the current name.
- Path A: press `IA_QUICKSAVE` (0 clicks, 1 key). No confirmation, and visible feedback is unknown.
- Path B: Esc → Save Game → Save (the name is pre-filled) → Accept in the overwrite dialog. That is 4 actions and 3 screens. The menu then closes.

T11. Save as a new name. Esc → Save Game → edit the name (typing) → Enter or Save. That is 3 clicks plus typing.

T12. Load the latest save of the current game.
- In game: Esc → Load Game → "Load Game" on the group card. That is 3 clicks, with no unsaved-progress warning. There is no quick-load.
- From the main menu: "Continue", 1 click.

T13. Load an older autosave. Esc → Load Game → card details → pick a row in the save list → Load Game. That is 5 clicks.

T14. Change GUI scale or autosave interval in game. Esc → Settings → Interface tab (or Advanced tab) → change the slider or combo box. That is about 4 clicks. It applies immediately. Back: 1 click, then Resume: 1 more.

T15. Rebind a hotkey. Esc → Settings → Keyboard tab → scroll or search under Key Mapping → click the binding → press a key → (Accept if there is a conflict). That is 5–6 actions.

T16. Quit to desktop. Esc → Quit → Return to Desktop. That is 3 clicks and no confirmation on PC. Whether an exit save is written by `app.quit(true)` needs in-game verification; `SaveGameType.Exit` exists (`savegame_react_util.tl:110`, `:768`).

T17. Jump from a statistics row to the world. The locate button next to the name moves the camera (`LocateButton`, `line_react_util.tl:209-235`). That is 1 click, and the statistics window stays open. Clicking the name instead opens the entity window, and the statistics window is shelved until that window closes.

## 3. Friction findings

| ID | Finding | Evidence | Impact |
|---|---|---|---|
| F-S1 | No bulk actions in any statistics table. No row selection, send-to-depot, replace or sell. Every fix needs a round trip to an entity window per row. | DataTable has no selection API (`builtin.d.tl:1160-1182`). Vehicle columns are display only (`statistic_vehicles.tl:358-371`). | High |
| F-S2 | No aggregate overview or KPIs. No totals row (total balance, total vehicles, average utilization), no count of loss-making lines and no line-level summary in the finance window. Finances are split by carrier only. | `statistic_lines.tl:403-415`; `finances_table.tl:583-588` (per carrier) | High |
| F-S3 | Money per line or vehicle is a single rolling 12-month number. No trend, no previous year, no revenue/cost split, no profit per vehicle on a line. | `line_react_util.tl:621-627`, `statistic_vehicles.tl:290-295` | High |
| F-S4 | Problems are fragmented across tabs, and the details hide behind a tooltip. Only the first problem is shown; several become "There Are Several Problems". There is no single "all warnings" list, and the Depots tab has no Problems column. | `statistics_react_util.tl:317-369`; `statistic_depots.tl:162-168` | High |
| F-S5 | Stations without lines are hidden from Station Statistics, so idle stations that cost upkeep cannot be found. | `statistic_stations.tl:256-264` | Med |
| F-S6 | The "Vehicles" column on Lines sorts by model-id list, not by vehicle count, so you cannot sort lines by fleet size. The vehicle count is shown only as an icon strip. | `statistic_lines.tl:262-275`, `:406` | Med |
| F-S7 | Balance display and sort may disagree. The cell shows `calculateBalance({lineEntity})`, but the sort uses `calculateBalance(getLineVehicles(line))`. After vehicles are moved or sold, the order may not match the numbers (needs in-game verification). | `line_react_util.tl:626` vs `statistic_lines.tl:289-294` | Low–Med |
| F-S8 | Station "Delay" is passenger-only, so there is no cargo-delay or spoilage column even though cargo lifetime matters (tutorial text `strings_en.tsv:2729`). | `statistic_stations.tl:160-162` | Med |
| F-S9 | Filters and sort are not saved with the game. They are kept in a recipe `useRef` only. Search is plain substring with no numeric filters (e.g. "Balance < 0", "Utilization < 30%"). | `statistics.tl:673-688`; `statistic_lines.tl:309-342` | Med |
| F-S10 | The statistics window is not movable and occupies the screen in "compact" mode. With the window shelved while an entity window is open, side-by-side work is impossible (needs in-game verification of the geometry). | `statistics.tl:653-656` | Med |
| F-S11 | Drill-down from the statistics window is one-way. No entity window links back to the matching statistics row. `openStatisticsWindow` takes only a tab key, with no entity or search argument. | `statistics.tl:691-693` | Low–Med |
| F-S12 | No hotkey for the Finance window (the statistics tabs have 7). | grep: only `openFinanceWindow` events from game-bar/radial (`game_bar.tl:111`, `:322`) | Low–Med |
| F-S13 | Finance table is fixed to 4 years with no per-line or per-cargo breakdown. Expanding carriers is click-per-carrier. | `finances_table.tl:572`, `:590-593` | Low |
| F-S14 | Depots "Maintained" click opens the vehicle manager without context (nil depot). | `statistic_depots.tl:57-68` | Low |
| F-S15 | The warehouse search keyword "empty" is a hard-coded English literal. | `statistic_warehouses.tl:381` | Low |
| F-S16 | Performance: every Lines/Vehicles cargo cell recomputes `calculateCargoColumnData*` independently (4× per row per 0.5 s, plus again for sorting). This may lag on large networks (needs in-game verification). | `statistic_lines.tl:96-198`, `:277-288` | Low–Med |
| F-M1 | No quick-load. Loading the last save in game takes 3 clicks through the pause menu. | `main/game.tl:790-796` (quicksave only); `pause_menu.tl:145-151` | Med |
| F-M2 | Quicksave gives no UI confirmation in Lua (log only), so the player cannot be sure it worked (needs in-game verification for an engine toast). | `main/game.tl:790-796` | Med |
| F-M3 | Saving under the current name always asks for overwrite confirmation, giving 4 actions for the most common save. Saving closes the menu. | `save_game_page.tl:70-88`, `:27-57` | Med |
| F-M4 | In-game Load and "Return to Desktop" / "Main Menu" have no unsaved-progress warning on PC (console only), so the player can lose unsaved progress. | `pause_menu.tl:160-213`; `savegame_react_util.tl:340-345`, `:1150-1153` | Med |
| F-M5 | The pause menu has no Mod Hub, gameplay-difficulty or "current save info" access, and the page set is hard-wired in local recipes. | `pause_menu.tl:125-221`, `:344-355` | Low |
| F-M6 | Settings changes in game need about 4 clicks plus a tab hunt. Search exists only for key bindings, not for settings in general. | `settings_page.tl:1650-1700` | Low |
| F-M7 | No notification preferences in Settings (e.g. mute categories or set thresholds). | grep `settings_page.tl` | Med (cross-ref notifications inventory) |
| F-M8 | Autosave is configurable (interval and keep count), but autosaves are not shown on the Save page because the page filters to manual saves. Overwriting or renaming an autosave into a manual save is not possible from Save. | `settings_page.tl:1235-1262`; `save_game_page.tl:163` | Low |

## 4. Improvement opportunities

How each change can be made:
- Tab replace: replace a statistics tab module recipe through a `react-replacement-config` resource whose `doReplaceFn` calls `ReplaceRecipe(original, replacement)` (`main/bootstrap_game.tl:12-49`). The tab modules return their recipe, e.g. `statistic_lines.tl:465`, so the original can be obtained with `ug_require`. This is medium effort (GloballyReplaceRecipe-style): the tab must be copied and maintained.
- Plugin: a `react-plugin` resource into an existing ExtensionPoint (`GameBarInfoDisplayExtension`, `game_bar/game_bar_widgets.tl:70-72`, examples in `game_bar/game_bar_display_*_plugin/*.res.lua`), or into `RadialMenuExtension` (`game_bar.tl:54`). This is easy.
- Event: fire existing events (`openStatisticsWindow`, `openVehicleManager`, `selectEntity`, `openFinanceWindow`). This is easy.

| # | Proposal | Saving | Moddability |
|---|---|---|---|
| I1 | "Network health" KPI strip in the game bar. Shows: number of loss-making lines, number of lines with problems, average utilization, and total 12-month line balance. Clicking it opens Line Statistics sorted by Balance ascending (event + preset sort). | T1/T5: 2–3 clicks → 0 to see, 1 to act | Easy: plugin into `GameBarInfoDisplayExtension` (`game_bar_widgets.tl:70`). The data APIs are already used in Lua (`api.engine.util.finance.calculateBalance`, `lineSystem.getLinesForPlayer`, notification state `statistics_react_util.tl:261-285`). Opening with a preset sort needs `initialFilterStates`, which is not exposed by the event (`statistics.tl:691`). It can be emulated by having the plugin keep its own window, or it needs a tab replace (medium). |
| I2 | Totals / summary row on Lines and Vehicles (sum of Balance, Vehicles, Capacity; average Utilization), plus a "count shown / total" label. | Reading an aggregate: impossible → 0 clicks | Medium: tab replace. DataTable has no footer, so put a BoxLayout above or below the DataTable inside the replaced tab (`statistic_lines.tl:436-462`). |
| I3 | Bulk actions on Vehicles statistics: a checkbox column plus "Send to depot / Sell / Replace selected", or act on all filtered rows. | T4: 3–4 clicks × N → ~3 + N checkbox clicks (or 3 for "all filtered") | Medium: tab replace plus a custom cell recipe. Commands go through `api.cmd` (send-to-depot and sell commands need confirming in `apidef/cmd.d.tl`; see the line_vehicle_mgmt inventory). DataTable has no selection, so the selection state lives in the tab recipe (pass a ref via `userParam`; note that userParam reaches only newly created cells, `builtin.d.tl:1170`). |
| I4 | Quick-filter chips: "Loss-making", "Has problems", "Utilization < X%", "Old/poor condition", "No vehicles". | Finding a subset: sort + scan → 1 click | Medium: tab replace. The replaced tab can define its own `fnUserFilter` (`statistic_lines.tl:456-458`). The shared header filter bar is local to `StatisticsContainer`, so either put the chips inside the tab or replace `StatisticsEntryPoint`, which is exported, to swap the entire window (higher effort). |
| I5 | Sort Lines by vehicle count and show the count as a number next to the strip. | Fixes F-S6, 0 extra clicks | Medium: tab replace (change `getVehiclesSortValue`, `statistic_lines.tl:262`). |
| I6 | Unified "Problems" tab: all Problem notifications across lines, vehicles, stations, towns, industries and warehouses, plus depots, in one sortable list with the full title per row and a jump action. | T5: up to 6 tab visits → 1 tab | Medium–hard. The tab list is hard-coded in local `makeTabDefinitions` (`statistics.tl:187-199`), so adding a tab means replacing `StatisticsEntryPoint` (exported, but everything inside is local, so effectively a copy). Alternative: a standalone window opened from a game-bar plugin (easy to medium), using `notification_util.getPersistingEntity2NotificationFromNative` (`statistics_react_util.tl:261-285`). |
| I7 | Show all stations, including unused ones, with a "No lines" badge, so idle upkeep is findable. | T7: impossible → 2 clicks | Medium: replace the stations tab and drop the `#lines > 0` condition (`statistic_stations.tl:259`). |
| I8 | Per-line finance history: a sparkline or last-year vs this-year column using `calculateBalance` with two time windows. | T2/T3: trend impossible → 0 clicks | Medium: tab replace. `api.engine.util.finance.calculateBalance(entities, from, to, bool)` already accepts arbitrary time windows (`statistic_lines.tl:290-293`). A revenue/cost split needs an API whose existence is unverified (needs check in `apidef/api/engine.d.tl`). |
| I9 | Cargo delay column on Stations (cargo quality per station group for non-passenger cargo). | Cargo spoilage diagnosis: hidden → visible | Medium: tab replace. `api.engine.util.cargo.getCargoQualityDataAtStationGroup(entity, cargoTypeId)` already takes a cargo type (`statistic_stations.tl:160-162`). Loop over cargo types. |
| I10 | Persist statistics filters and sort in the savegame, or at least across sessions. | Re-applying the filter each session: ~3 clicks → 0 | Medium–hard: state lives in a local ref inside `StatisticsEntryPoint` (`statistics.tl:673`). Needs a replacement of the exported `StatisticsEntryPoint` plus a game-script state for persistence. |
| I11 | Quick-load hotkey (load the most recent save of the current group) and a quicksave toast. | T12: 3 clicks → 1 key | Medium / needs verification. A toast can be added with an `IA_QUICKSAVE` handler in a plugin (`react.useInputAction` works in any mounted recipe, e.g. a game-bar plugin). A new input action ID (quickload) requires the engine's input-action list (`keyCmdDefinitions`, `settings_page.tl:664`), so whether mods can register new `IA_*` needs in-game verification. Fallback: a game-bar button plugin calling `app.findAllSavegames` + `savegame_react_util.groupSaves` + `app.loadGame` (APIs in `apidef/app.d.tl:63-80`). The button route is easy. |
| I12 | One-click "Save (overwrite current)" in the pause menu and/or a game-bar button that skips the overwrite dialog for the current save name. | T10 Path B: 4 → 1–2 | Easy as a game-bar plugin calling `app.saveGame(api.gui.game.getDefaultSavegameId(), cb, false)`. Changing the pause menu itself is hard, because `PauseMainPage` is local (`pause_menu.tl:57`); replacing `SaveGamePage` is medium (module return). |
| I13 | Confirmation (or auto exit-save) before in-game Load and before Return to Desktop / Main Menu on PC. | Prevents data loss; +1 click | Hard for Quit (local `PauseMainPage`). Medium for Load, by replacing `LoadGamePage` (module return, `load_game_page.tl:22`) and wrapping the card `onClick`. `SavegameCard` itself is exported through `savegame_react_util` but not a separate module return; needs a check whether `ReplaceRecipe` works on table members (it should, since it is keyed by recipe function, `react.lua:445-454`). |
| I14 | Finance-window hotkey and a "Lines" breakdown tab in Finances (top 10 earners and losers). | T9 +1 key; T1 via Finance | Hotkey: needs verification that a mod can define a new IA. A radial menu entry already exists. Breakdown tab: `FinanceAccount` is local (`account.tl:13`), so it means replacing the `FinanceTool` window (hard). Better delivered via I1 or I6. |
| I15 | Back-links from entity windows ("Show in statistics" focusing this row). | 3–4 clicks → 1 | Hard: `openStatisticsWindow` carries only a tab key (`statistics.tl:691`), and DataTable `scrollToRowKey` is available but the tab recipe needs a param for it. Requires replacing `StatisticsEntryPoint` plus the tab, plus a plugin in the entity window (see the entity_window inventory). |
| I16 | Settings shortcut: a game-bar or radial entry that opens the pause menu directly on the Settings page, or a mini panel with UI scale, autosave and celebrations. | T14: ~4 → 2 | Medium. The `openPauseMenu` event has no page argument (`main/game.tl:203`). A standalone mini panel can set app config only if an API is exposed. `SettingsPage` uses `app.getUserProfile()` / appConfig set functions (`settings_page.tl:1403-1432`); needs verification that mods may call them from game UI. |

Unknowns needing in-game verification:
- default key assignments of `IA_SELECT_STATISTICS_*`, `IA_QUICKSAVE` and `IA_MENU`;
- whether quicksave shows an engine toast;
- whether `app.quit(true)` / `app.stopGame()` write an exit save;
- the statistics window geometry in compact vs expanded mode;
- whether filter state survives save/load;
- whether mods can register new input actions;
- the Balance sort/display mismatch (F-S7);
- performance with many lines or vehicles.
