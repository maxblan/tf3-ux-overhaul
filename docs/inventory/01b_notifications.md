# 01b: Notifications, messages and warnings (TF3)

Scope: how the game tells the player about problems and events. Paths are relative to `SCR/game/`.
Abbreviations: `NM` = `game_mechanics/game_mechanics/notifications/`, `T` = `NM/types/`.

No dedicated "advisor" exists in the Lua sources. `gui/guidesystem/` holds only SFX defs (`guidesystem_sfx.gres.lua`). The context helper is covered in 01_shell_hud.md.

## 0. Architecture

- Model: a game script `NM/notifications.gs.lua` → `NM/notifications.script.tl` holds `NotificationsState` (`NM/notifications.d.tl:79-127`): a `notifications{id→Entry}` map plus a `history{id}` list. Each Entry has `timestamp`, `notification{type,params,autoDismissDuration,simParams}`, `persisting{entities}`, `dismissed`, `expired`, `tracked` and `playedInitialSound`.
- Two kinds:
  1. Event notifications (one-shot) are added with the script event `("Notifications","add")` (`notifications.script.tl:711-718`). They usually carry `autoDismissDuration = 60000` (`notification_util.tl:10`). The duration is compared against game time (`notifications.script.tl:85-93`), so how long it lasts on screen depends on game speed. Needs in-game verification.
  2. Persistent notifications (state-driven) are recomputed by the notifications script in 4 round-robin slices: `currentTick % 4` (`notifications.script.tl:13,49,121,180,260,420`). `updatePersistentNotifications` (`notification_util.tl:205-258`) diffs the new set against existing entries with `deepEquals(entities, persisting)` and `deepEquals(params)`. A new key creates a new entry. A vanished key gets `persisting=nil, dismissed=true, expired=true`. There is no autoDismissDuration, so they stay until the condition resolves or the player dismisses them.
- Type registry: each type is a pair `X.res.lua` (`type="notification"`, `guiType`, `label`, `simUpdateScript`, `initiallyIgnoredType`) plus `X.script.tl@useDataState` → `NotificationGuiData` (`notifications.d.tl:5-39`: title, description, icon, hudIcon, lvmIcon, iconExplainTooltip, previewImage, soundOnMount, onClick, wouldClick, progress). A `.sim.script@updateData` caches names (refreshed every 30 ticks per id: `notifications.script.tl:14,73`).
- Severity (guiType): `Info | Caution | Problem | Opportunity | Achievement | Unknown` (`notifications.d.tl:6-13`). The log labels them `Info / Warning / Error / Opportunity / Accomplishment / Unknown` (`NM/gui/notification_log.tl:196-203`).
- History cap: 100 entries. Persisting entries are never pruned (`notification_util.tl:7,160-178`).
- Ignore system (`notifications.d.tl:96-110`):
  - `ignored.fully=true` → no entry is created at all. Missions use this (`mission_x/mission/mission_sim.script.tl:789-806`).
  - `fully=false` (free game, `notification_legacy_util.tl:10-19`) → the entry is still created but `dismissed=true, tracked=false`. It is hidden from the popup ridge and the log, yet still shown as a HUD icon, an LVM icon and in the entity window (`notification_util.tl:145-146`).
  - The initial ignore set comes from `initiallyIgnoredType` in each `.res` (`notification_util.tl:31-42`).

### Where notifications surface (5 sinks)

| Sink | File | Filter | Clickable |
|---|---|---|---|
| Popup ridge (icon strip, hover card) | `NM/gui/notification_popups.tl:195-451`, mounted in `gui/gui/main/game.tl:58-66,519-529` | not `dismissed` | yes (click = jump, right-click = dismiss) |
| Notification log window | `NM/gui/notification_log.tl` | `tracked` (+ "Active" = not expired) | yes (row = jump, toggle = show/hide popup) |
| HUD icons above map entities | `notification_react_util.tl:116-167`, used by `gui/gui/main/hud_icon_toolbox.tl:33,362` | all persisting (ignores dismissed and tracked) | no: `setMouseTransparent(true)` (`notification_react_util.tl:148`). Hovering the entity gives the `iconExplainTooltip` text (`gui/gui/main/game_tooltips.tl:121-203`) |
| LVM per-line/vehicle icons | `gui/gui/line_vehicle_mgmt/line_react_util.tl:59-140` | persisting, guiType Problem or Caution | yes, `onClick(true)` |
| Entity window widget | `gui/gui/entity_window/entity_window_util.tl:2130-2160` | all persisting for that entity | yes (per entry) |
| Statistics "Problems" column | `gui/gui/statistics/statistics_react_util.tl:260-360`; columns in statistic_lines:405, stations:283, vehicles:360, industries:406, towns:498, warehouses:322 | only guiType == "Problem" (`statistics_react_util.tl:276`) | sortable column |

## 1. Surfaces

### 1.1 Notification popup ridge: `NotificationPopups` (`NM/gui/notification_popups.tl:195-451`)
- Purpose: the always-visible strip of notification icons over the map.
- Mounting: `NotificationsRidge` wrapper (`gui/gui/main/game.tl:58-66`), as a FloatingLayoutChild with h=-1, v=-1 (`game.tl:519-529`). CSS centres the list (`notifications.css.lua:284-287`), so the exact screen position needs in-game verification.
- Entry points: always present. On gamepad, `IA_NOTIFICATIONS_OPEN` toggles focus onto the list (`notification_popups.tl:204-209`; also forwarded from `game.tl:389-390`). `IA_BACK` leaves focus (`:213-215`).
- Status shown without clicks: only icons (32 px tiles), coloured by guiType class (`notifications.css.lua:43-46`; icon classes in `notification_react_util.tl:12-19`), with a progress ring for progress-type notifications (`notification_popups.tl:130-139`).
  - Title and description appear only on hover: `NotificationInfo` shows a 380 px card with title, description and progress bar (`notification_popups.tl:146-193,381-388`; `notifications.css.lua:258-267`).
  - No count badge, no grouping, no text.
- Ordering: oldest first, by ascending `timestamp` then id (`notification_popups.tl:267-273`), so new items are appended on the right.
- Capacity: `maxNumberOfvisibleNotifications = 18` tiles of width (`notifications.css.lua:45-46,288-291`), and the NavList scrollbar is `visibility="folded"` (`:293-295`). With more than 18 items the overflow is hidden. Whether the newest ones (right end) are cut off needs in-game verification.
- Actions:
  - Left-click an icon → `dataState.onClick(false)`: usually camera focus plus `selectEntity` with `stack=false`, which closes other entity windows (`notification_popups.tl:140`; `gui/gui/entity_window/view_manager.tl:617-624`). Clicking does not dismiss.
  - Right-click (`evt.button == 2`) or `IA_OPTION2` → dismiss (`notification_popups.tl:116-125`). This sends the `dismiss` event (`:284-289`).
- Sound: on first mount it plays `soundOnMount` or `notification_sfx.Initialize` once per notification, then marks `playedInitialSound` via the `initialSound` event (`notification_popups.tl:93-111`). On every unmount (resolve, dismiss or expire) it plays `Resolve` (`:112-114`; sounds in `NM/gui/sound/notification_sfx.gres.lua`). No sound plays during cutscenes (`:96`).
- Animations: slide-in into the ridge and a hover-card pop (`notifications.css.lua:48-60,269-274`).
- Update cadence: `useStepStateTimerWithCommit` re-reads native state (`notification_popups.tl:277`). The dismiss is optimistic: local state plus the command (`:284-289`).
- Moddability: `RegisterRecipe("NotificationPopups")`, a file-level local, has no ExtensionPoint. Changing it needs a `GloballyReplaceRecipe` of `NotificationPopups` / `NotificationIcon` / `NotificationInfo` (`gui/gui/main/bootstrap_game.tl:6-51`).

### 1.2 Notification log window: `NotificationLog` / `NotificationLogWindow` (`NM/gui/notification_log.tl:205-652`)
- Purpose: history and the "active" list of notifications, plus the per-type logging configuration.
- Entry points:
  1. The game-bar `NotificationButton` (exclamation icon, `NM/gui/notification_button.tl:37-56`), placed in the game-bar button rack, "notifications" slot (`gui/gui/game_bar/game_bar.tl:1263-1279`). Tooltip "Notifications" with the hotkey hint `selectNotifications`. The button is a `ToolButton`, so a second click closes the window.
  2. Hotkey input action `selectNotifications` (`notification_button.tl:35`; also forwarded at `game_bar.tl:1240,1429` and `game.tl:849`). The default key is not in the Lua sources; it is engine/config side (needs in-game verification).
  3. The radial menu entry "Notifications" (`game_bar.tl:157-166`, fires `openNotificationLog`).
  4. The react event `openNotificationLog` (`notification_button.tl:27-29`).
- Closing: the window close button, toggling the tool button again, `closeNotificationLog`, or `IA_CLOSE_TOPMOST_WINDOW` / `uiCloseAll` bubbling (allow-list `notification_log.tl:595-648`).
- Layout: a movable, closable window "Notifications", about 900 × 84vh, docked top-left with margin 80/100 (`notifications.css.lua:341-358`). It is a tool on the tool stack (`tool_react_util.registerToolWithWindow`, `notification_log.tl:652`).
- Status shown: one single-column DataTable "Message" (`notification_log.tl:533-575`). Each row shows a type icon, a show/hide-popup toggle and a scrollable description (`:30-121`).
  - The title is only an icon tooltip (`:42`).
  - The date is only visible on hover (overlay class `visible`/`invisible`, `:176-190`).
- Controls:
  - "Category" ComboBox: All / Info / Warning / Error / Opportunity / Accomplishment / Unknown (`:357-390`). It filters through `fnUserFilter` (`:561-573`).
  - ToggleButtonGroup History | Active (`:392-416`). History lists all `tracked` entries; Active lists tracked entries that are not expired (`:499`).
  - The settings cog `CheckboxListCallout` ("Configure Notification Logging"): a tree of guiType → individual types with checkboxes (`:450-481`). It sends `updateIgnoredTypes{ignoreFully=false}` (`:468-472`). It is disabled when `ignored.fully` is set (missions) (`:451,458-460`).
  - Per-row ToggleButton "Show/Hide Notification Pop-Up" → `enlist` / `dismiss` (`:62-78`, `:543-554`). It is disabled for expired rows in History (`:64,503-505`). `IA_OPTION2` also triggers it (`:60`).
  - Row click → `onClick(true)`, which stacks the entity window (`:106-111`).
- Sort: only by recency, newest first (`initialSortColumn = {1, true}`, compare on history index, `:491,501,557-560`).
- Filter state: kept between openings in a `useRef` in NotificationButton (`notification_button.tl:10,20-23`), but not across save and load.
- Missing: no text search, no group-by-entity or group-by-type, no counts per category, no bulk dismiss or "dismiss all", no "jump to next problem", no column for date, entity or severity.
- Moddability: `RegisterWrapperRecipe("NotificationLogWindow", builtin.Window, …)` (`:581`). This can be wrapped or replaced. `NotificationLog` / `NotificationLogEntry` / `NotificationLogMessage` are plain recipes, so changing them takes `GloballyReplaceRecipe`. The data API is public (`notification_util.externalGetNotificationsStateNative`, events `dismiss` / `enlist` / `updateIgnoredTypes`).

### 1.3 Game-bar notification button: `NotificationButton` (`NM/gui/notification_button.tl:9-58`)
- A static exclamation icon (`::/gui/game_bar/icons/circle_exclamation_mark_26.tga`). It has no badge, counter or severity colour, so the button never shows how many problems exist.

### 1.4 HUD notification icons on the map: `NotificationHudIcons` (`T/notification_react_util.tl:116-167`)
- Drawn by `HudIconMasterBase` for every entity that has a persisting notification (`gui/gui/main/hud_icon_toolbox.tl:27-45,350-367`). It uses a per-frame cache (`notification_react_util.tl:89-114`; created in `game.tl:127`).
- They are shown even for ignored or dismissed types, because the persisting map does not filter (`notification_util.tl:294-322`).
- Not clickable (`notification_react_util.tl:148`). The explanation text appears only by hovering the entity (`game_tooltips.tl:121-140,147-203`).
- Visibility follows HudIconMaster rules and zoom (engine), and needs in-game verification. DisableFeatures `HudIconMaster` can turn the master off (`gui/gui/main/disable_features.d.tl`).

### 1.5 LVM widget: `ManagerNotificationWidget` (`gui/gui/line_vehicle_mgmt/line_react_util.tl:105-140`)
- Shows icons per line or vehicle row for Problem + Caution types only (`:117-118`), with a tooltip of `iconExplainTooltip`. Clicking stacks the entity window (`:95-97`).

### 1.6 Entity-window widget: `NotificationWidget` (`gui/gui/entity_window/entity_window_util.tl:2130-2160`)
- Lists all persisting notifications for the entity as cards (`NotificationWidgetEntry`).

### 1.7 Statistics "Problems" column: `ProblemsCell` (`gui/gui/statistics/statistics_react_util.tl:346-360`)
- Sortable by count of guiType "Problem" only (`:260-310`). The tooltip shows the title, or "There Are Several Problems" (`:327`). Caution-level issues (overcrowded, stuck, condition, no road, cargo not unloaded) are not counted.

## 2. Notification type catalogue

Legend:
- Kind: P = persistent (state-driven, auto-resolves) or E = event (one-shot, auto-hides after 60 000 ms game time).
- Default: whether the type is visible in the popup ridge and log by default. Hidden means `initiallyIgnoredType = true`: HUD, LVM and EOW only.
- Click: what onClick does (default = `api.gui.camera.focusEntity` + `selectEntity`, from `notification_util.tl:436-471`).

### 2.1 Problem detectors (all persistent, computed in `notifications.script.tl:update`)

| # | Type (res label) | guiType | Default | Trigger and threshold | Title / text (EN) | Click |
|---|---|---|---|---|---|---|
| 1 | `line_warning` "Line Issue" | Problem | Hidden (`T/line_warning.res.lua`) | engine `api.engine.util.line.getLineProblems()` (ZERO_OR_ONE_STATION, DOUBLE_STATIONS, INCOMPATIBLE_STATIONS, NO_PATH, BAD_ALTERNATIVE_TERMINAL) plus `getLinesIssues(player,false)` (NowhereToLoad / NowhereToUnload / NoVehicleToLoadCargo / VehicleUseless / LineCargoConfig) → `lineProblem=-1`. Slice 0 (`notifications.script.tl:121-178`). | "Line Problem"; for example "Could not connect stations on {line}: {reason}.", "Line {line} contains too few stations.", "Line {line} is misconfigured." plus per-issue cargo lines (`T/line_warning.script.tl:6-142`) | focus on path-problem node position (`focusPosition(...,15)`) or the line, then the line window (`:183-205`) |
| 2 | `line_station_warning` "Station Issue" | Problem | Hidden | `getLineStationProblems()` (StopUseless, Passenger/Cargo/AllPassengerStopUseless, CargoTypeUnload/LoadUseless). Slice 1 (`:180-195`). | "Station Problem"; for example "Stop of {line} at {station} cannot be used with current vehicles." (`T/line_station_warning.script.tl:6-92`) | camera focus on line entity[1], opens station group window entity[2] (`:132-151`). The camera target looks odd: needs in-game verification |
| 3 | `town_warning` "Town Not Connected" | Problem | Hidden | `api.engine.util.town.getTownProblems()` (Disconnected / Overlength). Slice 1 (`:197-211`). | "Town Not Connected": "The road connection between {A} and {B} has been interrupted." / "Travel time between {A} and {B} is too long." (`T/town_warning.script.tl:5-22`) | alternates between town 1 and town 2 on repeated clicks (`:27-48`) |
| 4 | `town_rating_warning` "Town Rating Very Poor" | Problem | Visible | Rating is `critical`: VeryPoor, sticky while Poor (`towns/town_util.tl:754-762`). Slice 1 (`notifications.script.tl:224-238`). One entry per town × rating key. | "Town Rating Very Poor": 'The rating "{what}" of {town} is very poor and the residents are furious. Action should be taken immediately.' (`T/town_rating_warning.script.tl:36-42`) | town window |
| 5 | `town_rating_warning_nonperistent` "Town Rating Decreasing" | Caution | Visible | Rating level VeryPoor / Poor / Mediocre and not critical (`notifications.script.tl:240-248`). This is persistent despite the file name. It fires for any Mediocre rating, so it is not about a decrease. | "Town Rating Decreasing": 'The residents of {town} are concerned as the rating "{what}" is decreasing…' (`T/town_rating_warning_nonperistent.script.tl:29-35`) | town window |
| 6 | `vehicle_warning` "Vehicle Problem" | Problem | Hidden | `api.engine.util.vehicle.getVehicleProblems()` (NoPathElectric / Ship / Aircraft / Generic, Blocked). Slice 2 (`:260-275`). | "Vehicle Problem": "There is no electrified path for {vehicle}." / "The trains {t1} and {t2} are blocking each other." (`T/vehicle_warning.script.tl:5-62`). Bug: the long NoPathShip text without a name has no `return` (`:36`) and falls through to "An unknown vehicle problem occured." | vehicle window |
| 7 | `cargo_rtc_warning` "Cargo Not Unloaded" | Caution | Hidden | `simEntityAtVehicleSystem.getVehiclesWithRoundTripCount()`, meaning cargo rode a full round trip. Slice 2 (`:277-290`). | "Cargo Unload Problem": "{n} cargo of {vehicle} was not unloaded on line." (`T/cargo_rtc_warning.script.tl:26-45`) | vehicle window |
| 8 | `vehiclecondition` "Vehicle Condition" | Caution | Hidden | `getVehicleMaintenanceState(v) <= 0.2`, kept until > 0.3 (hysteresis via `wastedVehicles`) (`notifications.script.tl:292-322`). One entry per vehicle. | "Vehicle Condition": "The condition of {vehicle} is very bad." (`T/vehiclecondition.script.tl:82-95`) | 1 vehicle → vehicle window. Multiple → `openVehicleManager{openWithVehicleEntities}` (`:43-68`), but that branch is unreachable because each entry has one entity |
| 9 | `stuck_vehicle` "Vehicle Stuck" | Caution | Hidden | EN_ROUTE, not user-stopped, speed == 0 for ≥ 5 min of game time (`1000*60*5`) (`notifications.script.tl:534-575`). The IN_DEPOT case is commented out (`:553-554`), so the "stuck in depot" text (`T/stuck_vehicle.script.tl:46-48`) is dead. | "Vehicle Stuck": "{vehicleName} has been stuck for a while without moving." | vehicle window |
| 10 | `overcrowding` "Station Overcrowded" | Caution | Hidden | `api.engine.util.station.calculateStationGroupCargo(sg,-1).overflow` and at least one player line at the station (`notifications.script.tl:588-653`). The 1-min cooldown is commented out (`:640-652`), so it may flap. | "Station Overcrowded": "{stationName} is overcrowded, passengers will be leaving." (`T/overcrowding.script.tl:15-25`) | station window |
| 11 | `station_useless` "Station Not Usable" | Caution | Hidden | No terminal passenger load/unload and no catchables in the catchment, and the station has a player line (`notifications.script.tl:592-608,655-664`) | "Station Not Functional": "The station is not functional yet, as no warehouse, industry or town building is in the catchment area." (`T/station_useless.script.tl:30-40`) | station window |
| 12 | `noroadconnection` "Station Not Connected" | Caution | Hidden | `api.engine.util.line.getNoRoadConnectionProblems()`, re-evaluated only every 75 game days (`notifications.script.tl:16,421-436`), so it is slow to appear and slow to clear | "No Road Connection": "{stationName} is not connected to a road." (`T/noroadconnection.script.tl:20-29`) | station window |
| 13 | `industry_close` "Industry Closing" | Caution | Visible | `api.engine.util.industry.getClosingIndustries()` (`notifications.script.tl:438-452`). Progress shows the closure countdown (`closureCountdownTimeSpan`) (`T/industry_close.script.tl:31-42`). | "Industry Closing": "{industry} is complaining about insufficient workload and is urgently looking for a logistics partner… Otherwise the industry will soon close forever." / "closure was prevented" / "had to close its doors forever" (`:53-60`) | industry window |

### 2.2 Progress and status notifications (persistent)

| Type | guiType | Default | Trigger | Text | Click |
|---|---|---|---|---|---|
| `company/company_notification_prospection` "Prospecting" | Info | Hidden | `companyState.pendingProspections` (`notifications.script.tl:324-350`), plus E-variants for result/fail (`company/company.script.tl:111-118,151-160`) | "Prospecting Started / Failed / Successful" (`company_notification_prospection.script.tl:39-75`), progress | result industry or town |
| `company/company_notification_marketing` "Marketing Campaign" | Info | Hidden | town `eventFactors.marketingInitiatedTimestamp` within duration (`notifications.script.tl:352-385`). E "ended" from `towns/towns.script.tl:171-185` | "Marketing Campaign Started/Ended" | town |
| `company/company_notification_greenify` "Industry Greenification" | Info | Hidden | emissions `ecoLevels > 0` (`notifications.script.tl:387-416`) | "Improved Ecological Footprint" | construction |
| `subvention_notification` "Subsidy Status" | Opportunity | Visible | proposed / active / completed subventions (`notifications.script.tl:454-499`) | "Subsidy Available / in Progress / Effect Active" with progress bars (`T/subvention_notification.script.tl:101-115`) | `selectViewKey` subsidy view plus camera (`:81-95`) |
| `::/landmarks/landmarks_notification.script` | ? | ? | constructions with metadata, level below numLevels, with requirements (`notifications.script.tl:501-532`) | script/res not in the extracted sources (needs verification) | ? |

### 2.3 Event notifications (one-shot, `autoDismissDuration = 60000` game-ms)

| Type | guiType | Default | Sender | Text | Click |
|---|---|---|---|---|---|
| `subvention` "Subsidy Failed" | Opportunity | Visible | `subventions/subventions.script.tl:54-59` | subsidy title/description | subsidy view (`T/subvention.script.tl:54-76`) unless InvalidEntity |
| `subvention_missed` "Subsidy Missed" | Info | Visible | `subventions.script.tl:87-92` | subsidy description | none (`T/subvention_missed.script.tl:41-45`) |
| `availability` "New Vehicle" | Info | Visible | `NM/availability_notifications.script.tl:185-245` (yearFrom == current year, `notifyWhenAvailable`, grouped by `notificationGroup`) | "New Vehicle(s) Available": "{name} has hit the market…" plus a list, with preview image | opens Vehicle Manager at the first matching connected depot (`T/availability.script.tl:78-110`) |
| `con_availability` "New Construction" | Info | Visible | `availability_notifications.script.tl:249-327` | "New Construction Available", specials such as "Electric Trains Available", "Highways Available", "Traffic Lights Available" (`T/con_availability.script.tl:43-127`) | `constructionMenuSelectTabForConstruction` (`:32-40`) |
| `towns/town_notification` "Town Level Up" | Achievement | Visible | `towns/town_growth.script.tl:96-106` (plus fireworks) | "Town Level Up" | town; sound LevelUp |
| `company/company_notification_rank_up` "Company Rank Up" | Achievement | Visible | `company/company_growth.script.tl:99-106` | "Time To Celebrate: …promoted to {role}…" | `openCompanyWindow{unlockRank, initialTabKey="Company"}` |
| `industry_spawn` "Industry Founded" | Info | Visible | no Lua sender found (engine side? needs verification) | "New Industry Founded" | industry |
| `newcargodemand` "New Cargo Demand" | Info | Visible | no Lua sender found | "{town} has grown … now also require a new cargo type: {cargoName}." | town |
| `animaldespawn` "Animal Died" | Info | Visible | no Lua sender found | "A Grieving Day" | entity |
| `mission/notification` "Task Completed" | Achievement | Visible | `mission_x/mission/mission_sim.script.tl:719-743` (5000 ms or 60000 ms) | mission | none |

Defined param records with no type script: `CargoThrownAwayNotificationParams` (`T/notification_types.d.tl:190-197`). This is a dead "cargo thrown away" notification.

### 2.4 Dedupe and cooldowns
- Persistent types dedupe by `(entities, params)` deep equality (`notification_util.tl:225-236`). If params change, for example the vehicle set of a "Blocked" pair, the old entry expires and a new one is created, which pops up and plays a sound again.
- A dismissal sticks only as long as the identical key persists. Nothing silences an entity or type temporarily.
- Cooldowns: only `noroadconnection` (75 days). The overcrowding cooldown is disabled (`notifications.script.tl:640-652`). Stuck needs 5 min of continuous standstill.
- Retroactivity: `tracked` is fixed at creation (`notification_util.tl:146`). Enabling a hidden type in the log settings does not reveal problems that already exist, only newly created entries. This follows from the code and needs in-game verification.

## 3. Task flows

F1. "Is anything wrong right now?" (global status)
1. Look at the popup ridge, which shows icons only. With default settings it contains no line, vehicle, station or connection problems, because they are hidden. You would see town-rating, industry-closing, subsidy and availability icons.
2. Hover each icon to read it (1 hover per item; there are 18 slots).

Alternative: open Statistics → Lines/Vehicles/Stations tab → sort by the Problems column. That is 2–3 clicks per category and covers guiType "Problem" only.

Alternative: scan the map for HUD icons. They depend on zoom and cannot be clicked.

There is no single place listing all current problems with counts.

F2. "Why is line X broken?"
- Default: open the LVM → find the line → hover the LVM icon (tooltip) → click it → line window. That is about 3 clicks plus a search.
- If "Line Issue" logging is enabled: hover the ridge icon → click (1 hover + 1 click, camera jump plus line window).

F3. "Find all vehicles in bad condition"
- No list exists. Each vehicle is its own hidden notification. Statistics → Vehicles → Problems column does not include condition (Caution).
- Path: LVM, scanning vehicle rows for the repair icon one by one. Bulk repair or replace is not reachable from the notification (the `openVehicleManager` multi-select branch is unreachable, `T/vehiclecondition.script.tl:43-68`).

F4. "Which stations are overcrowded?"
- Hidden by default. Not in the Statistics Problems column (Caution). Only the HUD icon over the station or the LVM icon.
- Enabling it: game bar notification button → cog → expand Warning → tick "Station Overcrowded" (about 4 clicks), and it only applies to future occurrences.

F5. "Dismiss notification clutter"
- Right-click each icon one at a time. In the log, toggle each row one at a time.
- No dismiss-all, no dismiss-by-type, no snooze.

F6. "Jump to the problem and keep other windows open"
- A ridge click closes other entity windows (`stack=false`). A log row click stacks (`stack=true`). These behave inconsistently.

F7. "Review what happened while I was away"
- Notification button (or the `selectNotifications` hotkey) → History tab (default).
- Rows sort newest first. The date only shows on hover, there is no relative time, and the category filter is one combobox.
- Expired event notifications auto-hide after 60 s of game time, so you can miss them at high speed.

F8. "Turn off a noisy type" (for example Town Rating Decreasing)
- Notification button → cog → find the type under "Warning" → untick. That is 3–4 clicks, available in the log only, not from the popup itself.

## 4. Friction findings

| # | Impact | Finding | Evidence |
|---|---|---|---|
| N1 | High | Almost all operational problem detectors are hidden by default (`initiallyIgnoredType = true`): Line Issue, Station Issue, Vehicle Problem, Vehicle Condition, Vehicle Stuck, Station Overcrowded, Station Not Usable, Station Not Connected, Cargo Not Unloaded, Town Not Connected. In a fresh game, the popups and log show none of them. | `T/*.res.lua`; `notification_legacy_util.tl:10-19`; `notification_util.tl:145-146` |
| N2 | High | No aggregate problem overview or counter. The game-bar button is a static icon without a badge, and there is no "N problems" anywhere. | `NM/gui/notification_button.tl:37-56` |
| N3 | High | Missing problem classes: unprofitable lines or negative line balance, low or negative cash and loans, old vehicles past their lifespan (condition is maintenance only), lines with no vehicles, idle or stuck-in-depot vehicles (code commented out), long waiting times or under/over-capacity lines, cargo thrown away (record defined, no type). The APIs exist: `calculateBalance`, `getPlayersBalance` (`apidef/api/engine/util.d.tl:848,861`), `purchaseTime` / `lifespan` (`apidef/api/type.d.tl:1519,3958`). | `notifications.script.tl:553-554`; `T/notification_types.d.tl:190-197` |
| N4 | High | Ridge icons are opaque: title and description appear only on hover, there is no grouping by type or entity, and only 18 slots are visible with a folded scrollbar, so overflow is invisible. | `notification_popups.tl:146-193,267-273`; `notifications.css.lua:45-46,288-295` |
| N5 | High | The Statistics "Problems" column counts only `guiType == "Problem"`, so all Caution issues (overcrowded, stuck, condition, no road, cargo not unloaded, industry closing) cannot be sorted for. | `statistics_react_util.tl:276` |
| N6 | Med | No bulk actions: no dismiss-all, dismiss-by-type or snooze, and no "fix" actions (repair, replace, add vehicle) from a notification. | `notification_log.tl:62-78`; `notification_popups.tl:116-125` |
| N7 | Med | The log is a single "Message" column with no sort other than time, no search, and no per-entity grouping. The date is visible only on hover, and the title only as an icon tooltip. | `notification_log.tl:42,176-190,533-560` |
| N8 | Med | Enabling a hidden type does not retroactively surface existing problems, because `tracked` is fixed at creation. | `notification_util.tl:146`; `notifications.script.tl:741-764` |
| N9 | Med | "Town Rating Decreasing" fires for any Mediocre rating, which is static rather than decreasing. It is visible by default, which creates persistent noise and mislabels the state. | `notifications.script.tl:240-248` |
| N10 | Med | HUD icons on the map are mouse-transparent. You cannot click a warning icon to open the entity; you must click the entity itself. | `notification_react_util.tl:148` |
| N11 | Med | Event notifications auto-hide after 60 000 game ms, which is shorter in real time at high speed. | `notification_util.tl:10`; `notifications.script.tl:85-93` |
| N12 | Low | Inconsistent click semantics: a ridge click closes other windows (`stack=false`), a log or LVM click stacks. | `notification_popups.tl:140`; `notification_log.tl:111`; `view_manager.tl:617-624` |
| N13 | Low | Overcrowding has no cooldown (commented out), so it may flap and replay the Initialize/Resolve sounds. | `notifications.script.tl:640-652`; `notification_popups.tl:93-114` |
| N14 | Low | The no-road-connection check runs only every 75 game days, so fixes show up late. | `notifications.script.tl:16,424` |
| N15 | Low | Small bugs and dead code: NoPathShip falls through to "unknown" (`T/vehicle_warning.script.tl:36`); the vehicle-condition multi-vehicle branch is unreachable; the stuck-in-depot text is dead; line_station_warning focuses the camera on the line entity. | cited above |
| N16 | Low | "Subsidy Missed" has no click target. | `T/subvention_missed.script.tl:41-45` |

## 5. Improvement opportunities (with moddability)

| # | Proposal | Saving | Moddability |
|---|---|---|---|
| I1 | Flip the default ignore set: make the problem/caution detectors visible by default and keep only the flavour types hidden. | Problems go from invisible to 1 hover / 1 click | Easy. Override the `.res.lua` files (`initiallyIgnoredType=false`) via a mod `res` override. Existing saves need a `updateIgnoredTypes` event plus re-creating entries (fire `removePersistent`, or wait for the next diff). A small game script can send `("Notifications","updateIgnoredTypes",{ignoredTypes=…, ignoreFully=false})` once (`notifications.script.tl:741-764`). |
| I2 | Problem counter badge on the game-bar notification button, per severity (for example red Problem n, amber Caution n), with a click to open the log pre-filtered to Active + Problem. | 0 clicks for status; F1 from about 6 clicks to 0 | Medium. `NotificationButton` is a plain recipe (`notification_button.tl:9`), so use `GloballyReplaceRecipe` (`bootstrap_game.tl:6-51`, `react-replacement-config`). The data comes from `getPersistingEntity2NotificationFromNative` / `externalGetNotificationsStateNative` (`notification_util.tl:280-322`). Alternatively a new widget in a game-bar ExtensionPoint (see 01_shell_hud.md for available points). |
| I3 | "Problems" overview panel: active persistent notifications grouped by type with counts, expandable entity lists, click-to-jump (stacking), and bulk "dismiss type" / "snooze 1 year". | F3/F4 from not possible or many clicks to 2 clicks | Medium. A new tool window using `tool_react_util.registerToolWithWindow` (pattern in `notification_log.tl:652`), opened from a ModEntryPoint / MainModButtonArea extension point (`gui/gui/main/main_mod_button_area.tl:170`, `mod_entry_point.tl:110`). It reads the public state and sends `dismiss` events. |
| I4 | New detectors: unprofitable line (`calculateBalance(lineVehicles, now-1y, now)` < 0), low cash (`getPlayersBalance` < threshold), vehicle over lifespan (`purchaseTime` + model `lifespan`), line without vehicles, vehicle idle in depot (re-enable `notifications.script.tl:553-554`). | Surfaces status that is invisible today | Easy. A mod `.gs` game script that computes the sets and sends `("Notifications","updatePersistent",{type=…, entitiesAndParam=…})` (handler `notifications.script.tl:719-725`), plus a `notification` res and a `useDataState` script for each type. Statistics, LVM, EOW and HUD pick them up automatically through `persisting`. Performance of a full scan needs verification (slice it like the vanilla code). |
| I5 | Give Caution issues weight in the Statistics Problems column (or add a second "Warnings" column). | Sortable overcrowded/condition lists, F4 from impossible to 2 clicks | Medium. `getSortedProblemIds` is a file-local in `statistics_react_util.tl:260`, so replace `ProblemsCell` and the compare functions via GloballyReplaceRecipe plus a module patch. Feasibility depends on how statistic tabs reference `getProblemsCompareValue` (they import it from the util table, so patching `statistics_react_util.getProblemsCompareValue` at load may be enough; needs verification). |
| I6 | Ridge: show severity-grouped chips with counts ("Vehicle Problem ×7") instead of 1 icon per entity, a dismiss-all-of-type action on right-click, and a visible overflow indicator "+N". | Clutter from O(n) icons to O(types); dismiss from n clicks to 1 | Medium. GloballyReplaceRecipe `NotificationPopups` (`notification_popups.tl:195`) and adjust CSS (`notifications.css.lua:288-295`). |
| I7 | Log: add columns (date, severity, entity, type) with sort and search, a "dismiss all visible" button, and dates always visible. | F5 from n clicks to 1; F7 faster scanning | Medium. Replace `NotificationLog` (plain recipe, `notification_log.tl:205`) or wrap `NotificationLogWindow` (a wrapper recipe, `:581`). DataTable supports multiple `ColumnDesc` and `compareFn` already (`:533-575`). |
| I8 | Clickable HUD warning icons (click → onClick of the notification). | Map problem from 2 clicks (find entity, click) to 1 | Medium / uncertain. `NotificationHudIcons` uses `setMouseTransparent(true)` (`notification_react_util.tl:148`); replace the recipe. Whether HUD-icon layers accept mouse input is engine side and needs in-game verification. |
| I9 | Fix the "Town Rating Decreasing" trigger (only Poor or real decline) and re-enable the overcrowding cooldown. | Less noise | Easy–Medium. These live inside `notifications.script.tl:update`, which has no hooks. Either override the whole script file (medium, conflict-prone) or set the type to ignored (easy) and add your own detector (I4). |
| I10 | Uniform click semantics (always stack) and a "next problem" hotkey that cycles active Problem/Caution notifications with `camera.focusEntity`. | F2/F4 to 1 keypress per item | Medium. Hotkey needs an input action, and custom IA registration needs verification (see 01_shell_hud.md keybindings). Cycling uses the public state plus `api.gui.camera.focusEntity` and `fireReactEvent("selectEntity",{stack=true})` (`notification_util.tl:450-454`). |
| I11 | Auto-hide based on real time, or keep events until read. | Fewer missed events | Medium. Senders pass `autoDismissDuration`; set `-1`/nil via a wrapper, or change the expiry rule by overriding the script. |
