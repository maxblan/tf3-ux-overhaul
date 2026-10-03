# 01: In-game shell (game bar, HUD shell, hotkeys, window routing, notifications, layers)

Area: everything around the map while playing: the shell frame, the bottom game bar, game speed / money / date, context help, guides, music player, free camera, celebrations, all keybindings and how each major window is opened and closed.
Two sub-files go into more detail (summarised in §5):
- `01b_notifications.md`: notifications, warnings, popups, log, every notification type.
- `01c_layers_maphud.md`: the 11 map layers, the layer ridge, map HUD icons, tooltips and callouts.

Paths: `G=SCR/game/gui/gui`, `GM=SCR/game/game_mechanics/game_mechanics`, `MS=SCR/game/mission_x/mission`. `SCR/game/mission_x` holds the extracted `mission.zip` from the TF3 install, because the guide system and mission task list live there.
Keybindings: the physical keys are not in the Lua sources. Input actions come from the engine (`app.getInputActionRep()`, `G/menu/settings_page.tl:1645`; `InputActionDesc.defaultBindings`, `SCR/game/apidef/api/type.d.tl:3073-3094`). The keys below are read from a player's `settings_keys_v3.lua` (Steam userdata `.../3493540/local/`, copy at `SCR/settings_keys_v3.lua`, parsed into `SCR/keys_table.txt`). These are probably the defaults unless the player rebound something. Needs in-game verification.

## 0. Shell architecture (how the frame is built)

- Root: `GameUIProxyRoot` (`G/main/game.tl:723-1056`) is the default element (`game.tl:1060`). It holds:
  - `GameUIRoot` (`:872`)
  - `GameSpeedHelper` (`:886`)
  - `FreeCamOptions` (`:897`)
  - `DialogueOverlay` (`:907`)
  - `CalloutContainer` (`:913`)
- Global input actions are registered on the proxy root, so they work even when the game UI is hidden (`:746-849`). The proxy forwards them to `GameUIRoot` or to the `GameBar`.
- `GameUIRoot` (`game.tl:99-595`) builds the `GameContext` (`:173-188`) and lays out (`:409-594`):
  - `WindowContainerDelegate` (all windows)
  - `GameBar` (bottom)
  - `ToolStack` (see below)
  - `ReactAdapterGuestContainer`
  - `RendererComponent` (3D view)
  - `InspectorSelector` (map picking)
  - `ViewManager` (entity windows)
  - `GuideSystem`
  - `MissionTaskList`
  - `NotificationsRidge` (popup strip)
  - layer-button ridge + `MainModButtonArea` (top-left)
  - `MainRadialMenu` (centre)
  - hidden `EntryPoints` (Statistics / LineManager / VehicleStore entry points + mod plugins)
  - `CelebrationsContainer`
- ToolStack = the window manager for every "big" window (`G/main/builtin.lua:1197-1460`):
  - `push(tool, key, param, allowStacking)`: if `allowStacking` is false it first calls `clear()`, which pops every tool except the default pinned-entity-window tool (`builtin.lua:1383-1390`, `clear` at `:1352-1373`).
  - Every non-top entry gets shelved (`shelveNonTop`, `:1262-1285`). The standard shelve handler hides the window (`G/main/tool_react_util.tl:61-70`). Line Manager does the same (`G/line_vehicle_mgmt/manager_window.tl:8327-8334`).
  - Stacking flag per window:

    | Window (tool) | Pushed from | Stacks? |
    |---|---|---|
    | Finances | `game.tl:301` | no → clears others |
    | Company | `game.tl:323` | no |
    | Statistics | `G/statistics/statistics.tl:692,701` | no |
    | Line Manager | `manager_window.tl:8473` | no |
    | Construction menu | `G/construction/construction.tl:4867-4885` | only for module-bulldozer (`game_bar.tl:617`) |
    | Weather & Time | `game_bar.tl:37` | no |
    | Music Player | `game_bar_widgets.tl:169`, `game_bar.tl:154` | no |
    | Pause menu | `game.tl:196` | yes |
    | Free camera | `game_bar_widgets.tl:105` | yes |
    | Notification log | `GM/notifications/gui/notification_button.tl:17-25` | yes |
    | Entity window (map click, mouse) | `G/entity_window/view_manager.tl:604` | no (`stack=false`) |
    | Entity window (from a list) | e.g. `statistic_vehicles.tl:40`, `manager_window.tl:2162` | yes (`stack=true`) |
    | Layer tool | `layers_button_ridge.tl:223` | `stackTools` |

- Global UI event bus: windows open through `react.fireEvent(nil, "<event>", param)`, or `api.gui.fireReactEvent` from scripts. A mod can fire the same events to deep-link:
  - `openFinanceWindow` (tab: Overview / Finances / Assets / Loans / CargoLifetime; `GM/finance/account.d.tl:4-10`)
  - `openCompanyWindow` ({initialTabKey Company|Achievements, unlockRank})
  - `openStatisticsWindow` (Line / Vehicle / Station / Town / Industry / Warehouse / Depot; `G/statistics/statistics.d.tl:4-12`)
  - `openVehicleManager` ({openWithLineEntity, openWithDepotEntity, openWithVehicleEntities, sendToLineMode}; `G/line_vehicle_mgmt/manager_window.d.tl:143-148`)
  - `buyVehicles` / `replaceVehicles` / `modifyVehicles` (`vehicle_store_window.tl:4870-4932`)
  - `selectEntity` ({entity, stack})
  - `selectViewKey`
  - `openNotificationLog`
  - `openLayerRidge`
  - `openPauseMenu`
  - `closeAllWindows`
  - construction tabs `openRoad|openRail|openWater|openAir|openRoads|openTracks|openWarehouses|openPerks|openLandscaping|openTown|openIndustry` (each with an optional `sublistId`; `game_bar.tl:620-626`, `847-947`)
- Shell extension points (all `RegisterExtensionPoint*`; plugins are `react-plugin ::<Name>` generic resources sorted by `order`, `G/main/react.lua:93-117`):
  - `GameBarInfoDisplayExtension` (`G/game_bar/game_bar_widgets.tl:70`): the bottom-bar info strip. It is empty except for the two built-in plugins.
  - `MainModButtonAreaExtension` (`G/main/main_mod_button_area.tl:7`): a horizontal scroll row to the right of the Layers button, top-left (`game.tl:529-557`).
  - `RadialMenuExtension` (`G/main/radial_menu_extension.tl:6`, wrapper of `RadialMenuChild`): extra radial-menu entries (`game_bar.tl:54,182`).
  - `ModEntryPointExtension` (`G/main/mod_entry_point.tl:5`): mounted inside the invisible `EntryPoints` layer (`game.tl:574-587`, `meta.class="invisible"`). Suits headless logic, input actions and windows opened through `getDefaultWindowApi()` (`G/main/game_react_globals.tl:20-34`), not visible widgets.
  - Global recipe replacement: a `react-replacement-config` resource → `doReplaceFn(api)` → `api.ReplaceRecipe(orig, repl)` before init (`G/main/bootstrap_game.tl:6-53`, `react.lua:445-456`). `CallOriginalRecipe` works for non-builtin recipes (`react.lua:458-466`). `ToolStack` is a normal `RegisterRecipe` (`builtin.lua:1197`), so it can be replaced.
  - `DisableFeatures` flags (`CreateNewLine`, `GameSpeedControl`, `GameSpeedPause`, `HudIconMaster`, `Layers`, `OpenEntityWindow`, `PerkHudIcons`; `G/main/disable_features.d.tl`) are set with event `setDisableFeatures` (`game.tl:165-169`). Missions use them; a mod could too.

## 1. Surfaces

### 1.1 Game bar (bottom of the screen): `GameBar` (`G/game_bar/game_bar.tl:1390-1530`)
Anchored bottom-left, full width (`G/game_bar/game_bar.css.lua:40-50`). Background has four strips (`GameBarBackground`, `:197-207`). Parts:
1. Left: `GameBarMenuLeft` (`:499-554`)
   - Company button `CompanyButton` (`:378-491`):
     - Shows the rank title and a progress bar with % to the next rank. Level-up particles play while a rank is pending (`applyDiff>0`, `:424-428`).
     - Tooltip: "{percentage} of progress towards {role}." (`:466-469`).
     - Click toggles the Company window: ToolButton toolName "Company" → event `openCompanyWindow` / `closeCompanyWindow` (`:472-486`).
     - Hidden in missions and the map editor (`game.tl:435`).
     - Updates every frame (`useStepState`).
   - Finance button `FinanceButton` (`:290-332`):
     - Shows "Account" and the balance (`MoneyDisplay`, `:209-283`), red class "negative" when below 0 (`:242`).
     - The tooltip shows the alternative short/long money format (`:243`).
     - Click toggles the Finances window (`openFinanceWindow` → `FinanceTool` "Overview", `game.tl:290-302`).
     - In sandbox the balance is a click-to-edit spinbox (`:250-278`).
     - Updates every frame.
2. Context-help "?" toggle (`:1486-1511`):
   - Sits floating between left and middle. Its x position is recomputed every frame (`:1432-1446`).
   - Toggles the Context Help window (§1.6). Hotkey `IA_CONTEXT_HELP` (F1, `:1403`).
3. Middle: `GameBarMenuMiddle` (`:764-1070`). Upper row of icon ToolButtons (a tooltip shows the hotkey through `tooltipModifierInputAction`):
   - Line Manager `menu.managementMode` (key L, `IA_MANAGEMENT_MODE`, `:766-773,1025`) → `openVehicleManager` (`:580-585`).
   - [map editor only: heightmap / import / towns-industries / main-connections generators, `:793-836`]
   - Road (1), Rail (2), Water (3), Air (4) (`:839-880`).
   - Roads (5), Tracks (6), Warehouses (7) (`:884-921`).
   - Perks (8; not in missions, `:927-938`), Landscaping (9) (`:939-948`).
   - [sandbox / map editor: Town, Industry builders with no hotkey, `:952-974`]
   - Bulldozer (B) + Module bulldozer (B, hidden class `bulldozer-group`, `:977-998,1043-1049`).
   - Each construction button calls `constructionMenuSetTab {tabIndex}` (`:615-618`). It is disabled when the category is empty (`constructionMenuCategoryEmpty`, `:609-613,634`).

   Lower row: `GameBarInfoDisplay` (`game_bar_widgets.tl:71-89`), a horizontal scroll strip of plugins:
   - `GameBarEarningsPlugin`: "Earnings" = year-to-date earnings (`calculateEarnings`, doc `SCR/game/apidef/api/engine/util.d.tl:849-852`), green or red, polled every 0.5 s (`game_bar_display_earnings.script.tl:10-13`).
   - `GameBarTransportedPlugin`: total passengers and total cargo transported, icons with a hover tooltip, every frame (`game_bar_display_transported.script.tl:15-56`).
   - Both declare `priority = -2/-1` in their `.res.lua`, but the loader sorts by `order` (`react.lua:107-114`), so `priority` is ignored and their order is not guaranteed.
4. Right: `GameBarMenuRight` (`:1123-1388`)
   - Upper row:
     - 7 Statistics ToolButtons: Line F2, Vehicle F3, Station F4, Warehouse F5, Depot F6, Town F7, Industry F8 (`:1129-1192`). Each toggles the Statistics window on its tab (`openStatisticsWindow`/`closeStatisticsWindow`, `:1101-1106`).
     - Notifications button `NotificationButton` (`:1271-1279`; `selectNotifications`, F11 in the player's config). It has no badge or counter (see 01b).
     - Menu (burger) (`:1195-1211`): opens the pause menu and closes Context Help first.
     - Two hidden "fake" buttons for gamepad: `menu.radialmenu` (`IA_RADIAL_MENU`, `:1213-1224`) and `menu.inspector` (`IA_INSPECTOR`, `:1226-1237`).
   - Lower row:
     - Free Camera eye button (`game_bar_widgets.tl:92-110`, `selectCameraTool`, unbound).
     - Optional Advanced Camera toggle, shown only when `appConfig.cameraTool` is set (`game_bar.tl:1125-1127,1308`; `game_bar_widgets.tl:112-147`).
     - Music Player (`game_bar_widgets.tl:149-177`, `selectMusicPlayer`, unbound).
     - Game speed toggle group Pause / 1x / 2x / 4x with a gamepad keybinding hint (`game_bar_widgets.tl:179-256`).
     - Date + weather icon (`CalendarDisplay`, `:269-319`; MEDIUM date format; day/night icon by 06:00/19:00 and cloud cover). It is a ToolButton that toggles the Weather & Time window (`game_bar.tl:1355-1370`).
- Hidden or omitted per mode: money (map editor), Company (missions), Perks (missions), Line Manager, Infrastructure and Tracks (map editor) (`game.tl:430-457`).
- `isWelcomeScreenEnabled` is passed (`game.tl:456`) but never read. The context-helper script's `showWelcome` state (`G/context_helper/context_helper.script.tl:1-13`) is never read either. Both are dead code.

### 1.2 Game speed: `GameSpeedHelper` (`game.tl:617-719`) and `GameSpeedControl` (`game_bar_widgets.tl:179-256`)
- Speeds 0/1/2/4. `cycleSpeed` goes 1→2→4→1 (`game.tl:703-712`). `togglePause` restores the last non-zero speed (`:700-702`).
- Speed is clamped to `api.gui.game.getEstimatedMaximumGameSpeed()` (`:632-638,687-689`). The real throttle can be lower than the selected button with no visible explanation (the "throttle" is tracked internally, `:664-666`).
- Inputs:
  - `gamePause` (Space)
  - `gameCycleSpeed` (Tab)
  - `IA_GAME_PAUSE_OR_CYCLE_SPEED` (gamepad right stick: tap = pause, hold = cycle every 5 repeats; `:766-788`)
  - All three are disabled when `DisableFeatures.GameSpeedControl` is set (`:752-788`).
  - There is no direct hotkey for 1x / 2x / 4x.
- `DisableFeatures.GameSpeedPause` greys out the Pause button and forces the game to unpause (`:679-690`; `game_bar_widgets.tl:208-211`).
- The guide window pauses the game (speed 0) and restores the speed on close (`MS/guide_system/guide_system_react.tl:148-164`).
- No Lua sets speed 0 in the pause menu (`G/main/pause_menu.tl`). Whether Esc pauses the game needs in-game verification.

### 1.3 Weather & Time window: `CalendarEditorTool` / `CalendarEditorWindow` (`game_bar_widgets.tl:768-835`)
- Entry: click the date (`game_bar.tl:1355-1370`), radial menu "Calendar" (`:126-135`). No hotkey. Closes with the window X, a second click on the date, or a push of any other exclusive tool.
- Cards (`ContentCard`s, `:781-814`):
  - Weather: cloud slider; cycle Dynamic / Custom; "Skip To Next Weather" (`:515-606`).
  - Time of Day: sun slider, disabled in "Local" mode; cycle Dynamic / Continuous / Local Time / Custom; "Skip to Next Time of Day" (`:406-513`).
  - Calendar Speed: slider 0 / 0.25 / 0.5 / 1 / 2 / 4x (`:337-404`). This is separate from game speed, and the shell gives no hint of the difference.
  - Current Date (sandbox / editor only, `:677-766`).
  - Environment (sandbox / editor only, `:608-675`).
- The context-help page "calendar" exists (`context_helper_react.tl:457-464`).

### 1.4 Radial menu: `MainRadialMenu` (`game_bar.tl:47-195`)
- Entry: `IA_RADIAL_MENU` (gamepad Y only; no keyboard binding in the player's config). Shown centred (`game.tl:559-564`). It has `mouseSupport = true`, but PC players have no default way to open it.
- Entries:
  - Layers (`openLayerRidge`)
  - Statistics (first enabled tab)
  - Finances
  - Company
  - Calendar
  - Free Camera
  - Music Player
  - Notifications (`openNotificationLog`)
  - Mods (focuses `MainModButtonArea`; only when mod plugins exist)
  - plugins from `RadialMenuExtension`
- No Line Manager, Construction or Vehicle Store entries.

### 1.5 Pause menu: `PauseMenuTool` (`G/main/pause_menu.tl:57-435`)
- Entry: burger button (`game_bar.tl:1195-1211`), `IA_MENU` (Esc / Start) forwarded to `GameUIRoot` (`game.tl:803`; the handler is engine-side), event `openPauseMenu` (`game.tl:203-205`). Stacked push (`game.tl:196`).
- Buttons:
  - Resume
  - Save and Play (missions)
  - Save Game / Map
  - Load Game / Map
  - Settings
  - Return to Main Menu / Quit, both with a confirmation dialog (`pause_menu.tl:126-210`)
- Header "Game Paused - {savegameName}" and a `WallClock` (`:236-259,394`).
- `IA_MENU` / `IA_MENU_BACK` close it (`:117-121,409`).
- Quick save: `IA_QUICKSAVE` (F10) saves to the default savegame id without a dialog (`game.tl:790-796`).

### 1.6 Context Help window: `ContextHelperWindow` (`G/context_helper/context_helper_react.tl:809-908`)
- Entry:
  - "?" toggle in the game bar or `IA_CONTEXT_HELP` (F1) (`game_bar.tl:1403,1486-1511`)
  - `IA_GUIDE` is also F1. It has no Lua handler, only bubble-up filters.
- Behaviour:
  - Always-on-top, pinned, non-focusable side window (`:819,871-876`).
  - Every frame it collects which known UI ids are visible or focused (`api.gui.contextHelper.collectSubjectStates`, `:821-857`) and shows the help page of the most recently focused or visible one, with priority (`makeStateConfig`, `:763-807`).
  - Pages cover:
    - construction tabs
    - layers
    - finance tabs
    - company
    - calendar
    - subsidies
    - every entity-window type
    - Line Manager
    - Vehicle Store (priority 3)
    - each statistics tab
    - music player
    - notifications (`:28-720`)
  - Default page "HELP_START" (`:764-768`).
  - Only the bulldozer has a tool page (`:17-26`).
  - Resets the window position whenever the subject changes (`:831`).
  - Not closable in gamepad mode (`:864`).
- Mod note: the `pages` table is file-local (`:28`). Adding pages needs a replacement of `ContextHelperWindow` (a wrapper recipe).

### 1.7 Guide system (tips with "Ok, I got it!"): `GuideSystem` (`MS/guide_system/guide_system_react.tl:134-267`)
- Mounted in `GameUIRoot` (`game.tl:507-511`).
- Shows guides from the `guide_system.gs` mission script, newest first (`:17-45`). A guide is one of:
  - a free-positioned bubble (`trySpawnGuideFree`)
  - a bubble anchored to a UI id (`trySpawnGuideById`)
  - a modal `GuideWindow` (`:112-132`): not closable, a single "Ok, I got it!" button, and it pauses the game while open (`:148-164`)
- Cooldown 0.5 s between guides (`:144,207-224`).
- In free play the boot tasks are commented out (`MS/guide_system/main/guide_system.tl:7-11`). The only defined guides (build_stations, create_line, manager) are never booted (`MS/guide_system/main/guide_system_story.tl:6-70`), so free play normally shows no guides. Tutorial and missions use their own task lists.

### 1.8 Music Player window: `MusicPlayerTool` (`G/music_player/music_player.tl:17-285`)
- Entry: note button (lower right), radial menu, `selectMusicPlayer` (unbound). Exclusive push, so it closes Line Manager / Statistics / Finances when opened.
- Controls:
  - previous / play-pause / next
  - playlist combo (sorted by order then name)
  - mute toggle (`IA_OPTION1`) and volume slider
  - track time "m:ss / m:ss"
  - track label "{index} - {artist} - {title}"
- State polled every frame.

### 1.9 Free camera and advanced camera
- `FreeCamTool` (`G/main/free_cam_options.tl:36-48`): toggles the engine free camera or cockpit-follow.
- Exit with `IA_BACK` / `IA_MENU_BACK` (Esc / Mouse4/5), or when the follow action stops (`:12-28`). `IA_GAME_SCREENSHOT` (F9) works while active (`:19-23`).
- Advanced Camera (camera-manager window, engine) toggle only when `appConfig.cameraTool` is set (`game_bar_widgets.tl:112-147`). Its keys are the `camTool*` actions in the table below.

### 1.10 Celebrations: `CelebrationsContainer` (`GM/celebrations/celebration_react_util.tl:133-233`)
- Top-centre callout "Time to Celebrate!" with a type text (first delivery to town or industry, first passenger, town level-up, company promotion; `:28-77`) and a sound.
- Queued serially: each is shown 10 s, then a 1 s cooldown (`:134-135,185-201`).
- Left-click focuses the camera on the entity. Town level-up also opens the town window (stacked). Company promotion opens the Company window (`:114-128`).
- Right-click dismisses (`:80-86`).
- Global switch: `appConfig.enableCelebrations` (`:150-152`).

### 1.11 Mission task list (campaign): `MissionTaskList` (`MS/mission_framework/mission_framework_react.tl`, mounted `game.tl:512-516`)
- Bottom-left list of mission tasks. `IA_CAMPAIGN_MISSION_MENU_OPEN` (gamepad LB) (`game.tl:329-330,818`).
- It avoids overlapping the construction menu (`mission_framework_react.tl:948-960`).
- Not active in free play. Needs in-game verification.

### 1.12 Notifications (deep dive in `01b_notifications.md`)
- Popup strip `NotificationsRidge` / `NotificationPopups` (full-screen layer, `game.tl:59-67,517-528`):
  - icons only; title only on hover
  - left-click jumps the camera and opens the window, closing other windows
  - right-click dismisses
  - `IA_NOTIFICATIONS_OPEN` (gamepad RB) only focuses the strip (`game.tl:389-390`, `notification_popups.tl:204`)
- Notification log: opened from the game-bar button (stacked tool), the radial menu or `selectNotifications`.
- Most problem types are created already ignored in free play (01b §0), so the shell shows almost no operational problems by default.

### 1.13 Layers ridge and map HUD (deep dive in `01c_layers_maphud.md`)
- Top-left Layers button. Expanding it takes 1 click and picking a layer takes another.
- One exclusive layer at a time.
- Numpad hotkeys per layer (`game.tl:215-226`, forwarded `:806-816`).
- `MainModButtonArea` sits right next to it (`game.tl:554`).

### 1.14 Inspector, map picking and entity windows (routing only; the windows themselves are in 04)
- `InspectorSelector` (`G/main/selector_react_util.tl:243`) → `makeDefaultSelector` (`:88-150`).
  - A left-click on an entity fires `selectEntity {stack = gamepad ? true : false}` (`:108,123`).
  - `ViewManager` (`G/entity_window/view_manager.tl:617-626`) → `openWindow(..., doCloseAll = not stack)` (`:556-604`).
  - On PC, a map click calls `closeAll` (keeps pinned windows only, `:525-555`) and pushes without stacking → `ToolStack.clear()`. That closes Statistics, Line Manager, Finances, Construction, Music, Calendar and the like.
- Pinning an entity window calls `ToolStack.clear()` (`view_manager.tl:498-509`), which also closes every open tool window.
- A depot without a maintenance pool opens the Line Manager in depot mode instead of a window (`view_manager.tl:559-567`).

### 1.15 Global close
- `uiCloseAll` (Delete): `api.gui.closeAllWindows()`, aborts dialogue, stops credits (`game.tl:228-235`).
- `IA_CLOSE_TOPMOST_WINDOW` (Esc, Mouse4/5) is handled engine-side.
- Esc is bound to `IA_MENU`, `IA_MENU_BACK`, `IA_CLOSE_TOPMOST_WINDOW`, `IA_CONSTRUCTION_ACTION_CANCEL` and `IA_SKIP_VOICEOVER_AND_CUTSCENE` at once. Which one wins is engine priority and needs in-game verification.

### 1.16 Keyboard and mouse bindings (from the player's `settings_keys_v3.lua`; gamepad in brackets)
Settings UI: Settings → Key Mapping, mouse mode only. Categories are General, Game, Campaign, Statistics, Layers, Construction, Camera and Camera Tool, with a text filter and conflict detection (`G/menu/settings_page.tl:91-100,131-210,1641-1660`). Only actions with a non-empty `uiCategory` are listed. The ids are engine-defined; The code shows no way for a mod to register new input actions (needs verification).

| Area | Action id → key | Handler / effect |
|---|---|---|
| Speed | `gamePause` Space; `gameCycleSpeed` Tab; `IA_GAME_PAUSE_OR_CYCLE_SPEED` [RS] | `game.tl:752-788` |
| Save | `IA_QUICKSAVE` F10 | `game.tl:790-796` |
| Menu | `IA_MENU` Esc [Start] | pause menu (engine → `openPauseMenu`) |
| Close | `IA_CLOSE_TOPMOST_WINDOW` Esc/Mouse4/Mouse5 [B]; `IA_MENU_BACK` same; `uiCloseAll` Delete; `IA_CLOSE_ALL_LONGPRESS` [hold B] | `game.tl:228-235` |
| Help | `IA_CONTEXT_HELP` F1 [LS]; `IA_GUIDE` F1 | context help toggle (`game_bar.tl:1403`) |
| Line Manager | `IA_MANAGEMENT_MODE` L | `game_bar.tl:773,1406` |
| Statistics | `IA_SELECT_STATISTICS_LINES` F2, `_VEHICLES` F3, `_STATIONS` F4, `_WAREHOUSES` F5, `_DEPOTS` F6, `_TOWNS` F7, `_INDUSTRIES` F8 | toggle the stats tab (`game_bar.tl:1130-1191`) |
| Notifications | `selectNotifications` F11; `IA_NOTIFICATIONS_OPEN` [RB] | log / popup focus |
| Construction | `selectRoad` 1, `selectRail` 2, `selectWater` 3, `selectAir` 4, `selectRoads` 5, `selectTracks` 6, `selectWarehouse` 7, `selectPerks` 8, `selectTerrain` 9, `selectBulldozer` B [B], `selectModuleBulldozer` B [X] | `game_bar.tl:1407-1417` |
| Construction tools | `constructRaise` . / Num+, `constructLower` , / Num-, `constructNoSnap` C, `constructAlignToTerrain` T, `constructOpt1` M, `constructOpt2` N, `constructOpt5` O, `constructOpt6` P, `constructOpt7` [, `constructOpt8` ], `IA_UNDERGOUND_MODE_TOGGLE` G, `IA_PRECISION_MODE` Shift, `IA_SECONDARY_MODE` Ctrl, `IA_ENHANCED_SNAP` Alt, `IA_INVERT_ACTION` <, `dummyModifierMultiselect` Ctrl | construction area |
| Layers | `IA_TOGGLE_LAYER_TERRAIN` Num0, `_CIVILIZATION` Num1, `_INFRASTRUCTURE` Num2, `_TRAFFIC` Num3, `_PASSENGER_FLOW` Num4, `_PUBLIC_TRANSPORT` Num5, `_CARGO_FLOW` Num6, `_CARGO` Num7, `_NOISE` Num8, `_POLLUTION` Num9; `IA_TOGGLE_LAYER_BUTTON_RIDGE` unbound | `game.tl:215-226` |
| Camera | `cameraMoveUp/Down/Left/Right` W/S/A/D, `cameraRotateLeft/Right` Q/E, `cameraTiltUp/Down` R/F, `cameraZoomIn/Out` X/Z; `cockpitCameraPosNext/Previous` PgUp/PgDn; `cockpitCameraHorn` H; `IA_GAME_SCREENSHOT` F9 | engine |
| Camera tool | `camToolAddKeyframe` Insert, `camToolCapture` Enter, `camToolStartRecording` Enter, `camToolClearKeyframes` Home, `camToolPlayPause` Space, `camToolStop` Backspace | engine |
| Unbound shell actions | `selectMusicPlayer`, `selectCameraTool`, `IA_TOGGLE_LAYER_BUTTON_RIDGE`, `IA_RADIAL_MENU` (pad only), `IA_INSPECTOR` (pad only) | |
| No action exists at all | open Finances, open Company, open Weather & Time, open Vehicle Store, New Line, set speed 1x/2x/4x directly, jump to next problem | |
| Debug (Right Alt+…) | D debug window, G toggle GUI, R reload defs, Shift+R reload react, T shaders, L lanes, B bounding boxes, I timings, V develop town, Y new town buildings, Z camera manager window, A/F1 component dump; `uiConsole` ` (grave) | |

Hotkeys can be discovered only through the hover tooltip (`tooltipModifierInputAction`, e.g. `game_bar.tl:635,1092,1199`). The game bar has no keyboard-shortcut overlay or cheat sheet.

## 2. Task flows (PC, mouse+keyboard; C = clicks, K = key presses, S = windows, X = context switches)

| # | Goal | Path | Cost |
|---|---|---|---|
| T1 | Pause / resume | Space, or click the Pause button | 1K or 1C |
| T2 | Go to 4x | Click 4x (1C), or Tab up to 2x from 1x (1→2→4) | 1C / 1–3K |
| T3 | Check cash | Glance bottom-left (balance only, red if <0); hover for the alternative format | 0 |
| T4 | Check this month's profit / cash flow | Not shown in the shell. "Earnings" is year-to-date. Click Finance button → Overview (1C, 1S) → Finances tab for the breakdown (+1C) | 1–2C, 1S |
| T5 | See whether anything is wrong | No shell indicator. Notification button / F11 → log (1C) → change category / Active toggle (+1–2C). Most problem types are ignored by default (01b), so they must first be enabled per type through the cog (+3–4C, one-time). Alternative: F2 Line statistics → Problems column (counts guiType "Problem" only, 01b) | 2–6C, 1S |
| T6 | Find why line X is unprofitable | No notification exists (01b). F2 → sort or scan lines by profit (statistics area) → click line → line window opens and Statistics is shelved, i.e. hidden (`builtin.lua:1262-1285`, `tool_react_util.tl:61-70`) → inspect → close → Statistics reappears | ≥4C, 2S, 2X per line |
| T7 | Open the Line Manager for one line | L (1K) → search or scroll the list → select. From a line window there is a button (other area). Deep-link event `openVehicleManager{openWithLineEntity}` exists but has no shell entry | 1K + 2–3C |
| T8 | Compare a list with entity details side by side | Not possible with Statistics or Line Manager: opening an entity from the list shelves (hides) the list. Pinning the entity window calls `ToolStack.clear()` and closes the list (`view_manager.tl:507-509`) | n/a |
| T9 | Keep Line Manager open and click a vehicle on the map | Map click on PC → `closeAll` + non-stacking push → `clear()` → Line Manager closes (`selector_react_util.tl:108`, `view_manager.tl:581-604`, `builtin.lua:1383-1390`) | reopen: +1K (L) + navigation |
| T10 | Build something while looking at statistics | Press 1..9 → construction push clears Statistics (`construction.tl:4867-4885`) | Statistics lost; reopen +1K |
| T11 | Change music track while managing lines | Note button → Music window → Line Manager closes (exclusive push, `game_bar_widgets.tl:169`) | +1K + navigation to restore |
| T12 | Change weather / time of day | Click date (1C) → Weather & Time window → combo/slider (1–2C); also closes other tool windows | 2–3C, 1S |
| T13 | Toggle a map layer | NumpadN (1K), or Layers button → pick (2C) (01c) | 1K / 2C |
| T14 | React to a notification popup | Hover the icon to read it (0C, hover) → left-click: camera jump + entity window, closing other windows (01b) → right-click to dismiss (1C) | 1–2C |
| T15 | Check company rank progress | Glance (progress bar); hover for the % text; click for the Company window (1C) | 0–1C |
| T16 | Learn what a window does | F1 / "?" (1K) → window follows the focused UI | 1K |
| T17 | Save quickly | F10 (no feedback in Lua besides the log, `game.tl:790-796`) | 1K |
| T18 | Close everything | Delete (1K) | 1K |
| T19 | Free camera | Eye button (1C) or radial menu; Esc to exit | 1C+1K |
| T20 | Open radial menu (PC) | No default binding, so effectively unavailable | n/a |

## 3. Friction findings

| # | Finding | Evidence | Impact |
|---|---|---|---|
| F1 | Single exclusive tool slot. Opening any of Finances, Company, Statistics, Line Manager, Construction, Weather & Time or Music Player closes all the others. Even the music player kills an open Line Manager. | `builtin.lua:1383-1390` + non-stacking pushes `game.tl:301,323`, `statistics.tl:692,701`, `manager_window.tl:8473`, `construction.tl:4867-4885`, `game_bar.tl:37,154`, `game_bar_widgets.tl:169` | High |
| F2 | Parent list hidden while viewing a child. Entity windows opened from Statistics or Line Manager are stacked, so the list tool is shelved and its window `setVisible(false)`. No side-by-side drill-down. | `builtin.lua:1262-1285`, `tool_react_util.tl:61-70`, `manager_window.tl:8327-8334`, `statistic_vehicles.tl:40`, `manager_window.tl:2162,2324` | High (needs in-game verification) |
| F3 | Map click on PC closes every tool window and all unpinned entity windows. Stacking is only on for gamepad. | `selector_react_util.tl:108,123`, `view_manager.tl:525-604` | High |
| F4 | Pinning an entity window closes all tool windows (`clear()`). | `view_manager.tl:498-509` | Med |
| F5 | No at-a-glance health status in the shell. The bar shows only balance, YTD earnings and lifetime passengers/cargo. Missing: problem count, cash-flow trend, loan, unprofitable lines, broken or old vehicles. The notification button has no badge. The engine already exposes `getProblemLines`, `getLinesIssues`, `getNoPathVehicles`, `calculateBalance`, `calcIncomeSince`. | `game_bar_display_*.script.tl`, `NotificationButton` (01b §1.3); APIs `SCR/game/apidef/api/engine/system.d.tl:43,374`, `engine/util.d.tl:240-248,827-838` | High |
| F6 | Problem notifications ignored by default (line, station, vehicle, stuck, overcrowded…). Players are not told about breakage. | 01b §0, `notification_util.tl:145-146` | High |
| F7 | Missing hotkeys for Finances, Company, Weather & Time, Vehicle Store, New Line, direct speed set. Music and camera tool have actions but no default key. The layer ridge has no key. The radial menu, which already groups these, is gamepad-only on PC. | §1.16; `game_bar.tl:1213-1224` | Med |
| F8 | "Earnings" label hides that it is year-to-date. It resets each January, with no tooltip about the period (tooltip is "Total Earnings"). | `game_bar_display_earnings.script.tl:24-34`, API doc `util.d.tl:849` | Med |
| F9 | Game speed tops out at 4x and is silently throttled when the machine is slow (`getEstimatedMaximumGameSpeed`). No UI shows the actual speed. | `game.tl:632-638,664-666,687-689` | Low/Med |
| F10 | Calendar speed (date progression 0–4x) is buried in the Weather & Time window. It is easy to confuse with game speed, and its state is not shown in the bar. | `game_bar_widgets.tl:337-404` | Low |
| F11 | Celebrations queue serially (10 s + 1 s each) in top-centre screen space. A burst of firsts can occupy the top of the screen for minutes. The only off switch is an app config flag. | `celebration_react_util.tl:134-201,150` | Low/Med |
| F12 | The guide window is modal-ish: not closable, pauses the game, and is dismissed only by "Ok, I got it!". It is dormant in free play (boot tasks commented). | `guide_system_react.tl:112-164`, `guide_system.tl:7-11` | Low |
| F13 | Esc is bound to five actions; F1 to two (`IA_CONTEXT_HELP`, `IA_GUIDE`); B to two (`selectBulldozer`, `selectModuleBulldozer`). Behaviour depends on engine priority. | keys table | Low (verify) |
| F14 | Hotkeys can be discovered only by hovering each button. There is no shortcut overview. | `tooltipModifierInputAction` usage | Low |
| F15 | The context help page set is a file-local table, so mods cannot add pages without replacing the whole window. | `context_helper_react.tl:28` | Low |
| F16 | Plugin ordering in `GameBarInfoDisplayExtension`: the built-ins use `priority`, which the loader ignores (it sorts by `order`), so ordering is undefined. A mod must use `order`. | `react.lua:107-114`; `game_bar_display_*.res.lua` | Low (mod note) |
| F17 | Dead "welcome screen" plumbing (`isWelcomeScreenEnabled`, `showWelcome`). There is no onboarding in free play. | `game.tl:456`, `context_helper.script.tl` | Low |
| F18 | `ModEntryPointExtension` plugins render inside an invisible container, so visible mod widgets must use `MainModButtonArea`, `GameBarInfoDisplay` or windows. | `game.tl:574-587` | Low (mod note) |

## 4. Improvement opportunities (with moddability)

| # | Proposal | Saving | Moddability |
|---|---|---|---|
| I1 | Status strip in the game bar: cash-flow this month and last month (`calcIncomeSince` / `calculateBalance`), loan, # problem lines (`getProblemLines`), # line issues (`getLinesIssues`), # no-path vehicles (`getNoPathVehicles`), # vehicles past lifespan. Each item is clickable and deep-links: `openStatisticsWindow "Line"`, `openFinanceWindow "Finances"`, `openVehicleManager{openWithVehicleEntities}`. | "Is anything wrong?" goes from 2–6C (T5) to 0 (glance), and drill-down to 1C | A `react-plugin ::GameBarInfoDisplayExtension` with an `order` field (`game_bar_widgets.tl:70`). Polling should use `useStepStateTimer` (`engine_react_util.tl:126-157`) to stay cheap. |
| I2 | Quick-launch row (top-left next to Layers): Finances, Company, Weather, Vehicle Store, Notifications log, "next problem" button, 1x/2x/4x/8x buttons. | Opening a window without a hotkey: 1C, but discoverable. Speed set: 1C instead of 1–3K | A `MainModButtonAreaExtension` plugin (`main_mod_button_area.tl:7`). Events per §0. Speed via `api.cmd.makeGameSetSpeedCmd(n)`, which `GameSpeedHelper` re-syncs every step (`game.tl:640-652`). Whether speed >4 works needs verification. |
| I3 | Non-exclusive, side-by-side windows: let Statistics, Line Manager, Finances, Music and Weather stack, and stop shelving from hiding them. | T6/T8/T9/T10/T11: saves 1K + navigation each time; enables list+detail workflows | Replace the `ToolStack` recipe (`builtin.lua:1197`, normal RegisterRecipe) through `react-replacement-config`. Copy about 260 lines, then make `push` stack for whitelisted tool names and make `shelveNonTop` skip hiding. Watch out for tools that rely on exclusivity (construction). |
| I4 | Map click keeps tool windows: pass `allowStacking=true` for mouse picks, or only when Ctrl is held (`dummyModifierMultiselect`). | T9: saves reopening the Line Manager each click | Replace `InspectorSelector` (`selector_react_util.tl:243`). `makeDefaultSelector` already takes `allowStacking` (`:88`). Needs I3 so stacked windows stay visible. |
| I5 | Pin without closing tools | T8 | Needs a `ViewManager`/entity-window replacement (`view_manager.tl:498-509`) or I3's ToolStack replacement where `clear()` spares whitelisted tools. |
| I6 | Problem-first notifications: un-ignore problem types by default, badge on the button. | T5: 2–6C → 0–1C | Override notification `.res.lua` defaults; badge needs `GloballyReplaceRecipe(NotificationButton)` (see 01b §5). |
| I7 | Earnings tooltip / period clarity, plus a second plugin "This month" | F8 | A separate `GameBarInfoDisplayExtension` plugin. Changing the built-in label needs a replacement of `GameBarEarningsPlugin` (a registered plugin recipe). |
| I8 | Shortcut cheat-sheet overlay listing all bound actions and keys | F14 | A window from a `MainModButtonArea` button. The list comes from `app.getInputActionRep()` (as in `settings_page.tl:1645-1660`) and the bindings from app config `keyCmdDefinitions` (`:131`). Whether those are readable from in-game UI needs verification. |
| I9 | Hotkeys for unbound or missing actions | F7 | Existing unbound actions (`selectMusicPlayer`, `selectCameraTool`, `IA_TOGGLE_LAYER_BUTTON_RIDGE`): the player can bind them in Settings (only if they have a `uiCategory`; verify). New actions (Finances, Company, etc.): likely not feasible, because input actions are engine-defined (`InputActionRep`). Workaround: I2 buttons, or a command palette (I10). |
| I10 | Command palette / jump-to window (type a line, station or town name → open its window, line manager, statistics tab or construction tab) | Saves 2–5C per navigation | A window opened from a `MainModButtonArea` button. Entities via `api.engine.system.lineSystem.getLinesForPlayer` (`system.d.tl:18`), opening via `selectEntity` / `openVehicleManager` / `constructionMenuSetTab` events. A dedicated hotkey is limited by I9. |
| I11 | Radial menu on PC (it already has `mouseSupport`) plus entries for Line Manager, Vehicle Store and Construction | F7 | Entries via `RadialMenuExtension`. Opening it on PC needs a binding for `IA_RADIAL_MENU` (settings, if exposed) or a replacement of `GameBarMenuRight` (`game_bar.tl:1123`) to make its fake button reachable. |
| I12 | Celebration throttle: collapse queued celebrations into one summary callout, or shorten to 4 s | F11 | Replace `CelebrationsContainer` (`celebration_react_util.tl:133`). |
| I13 | Real-speed indicator (shows "throttled to 2x" when `getEstimatedMaximumGameSpeed` < selected) | F9 | A `GameBarInfoDisplayExtension` plugin that reads the `GAME_SPEED` component like `game.tl:644`. |
| I14 | Context-help pages for mod UIs | F15 | Replace `ContextHelperWindow` (wrapper recipe; `pages` table is local). |

## 5. Sub-file summaries

01b, notifications (`01b_notifications.md`):
- Problem types are `initiallyIgnoredType=true` in free play: line issue, station issue, vehicle problem / condition / stuck, station overcrowded / not usable / not connected, cargo not unloaded, town not connected. They show only as HUD icons that can't be clicked, plus Line Manager, entity-window and Statistics widgets.
- Popups: icons only, at most 18, text on hover. Left-click jumps the camera and closes windows. Right-click dismisses.
- Log: one column, category filter, History/Active toggle. No search, counts or dismiss-all.
- No notification at all for unprofitable lines, low cash or loan, old vehicles, lines without vehicles, or idle vehicles in a depot.
- Mod hooks: a new detector needs only a game script and a notification res. A badge or overview needs a recipe replacement.

01c, layers and map HUD (`01c_layers_maphud.md`):
- 11 exclusive layers; 2 clicks by mouse or 1 numpad key. Only the HUD filter persists; layer options reset on open.
- Map HUD shows: vehicle state and load, industry and warehouse stock, town growth, warning icons, waiting passengers at stations (not cargo).
- Map HUD does not show: unprofitable lines/vehicles. The meaning of a warning is hover-only.
- Plugin hook: `MainModButtonAreaExtension` for quick layer and filter toggles.
- Replacement hooks: `HudIconMasterGame`, `DefaultEntityToolTip` or `ExpandableLayerButton`.

## 6. Unknowns needing in-game verification
- Default key bindings (taken from the player's file).
- Whether Esc opens the pause menu or closes the top window first.
- Whether the pause menu pauses the game.
- That shelving really hides Statistics or the Line Manager while an entity window is on top (F2).
- That a map click closes the Line Manager (F3).
- Whether `makeGameSetSpeedCmd(8)` is accepted.
- Whether mods can define new input actions.
- Whether `IA_RADIAL_MENU`, `selectMusicPlayer` and `selectCameraTool` appear in the Key Mapping settings.
