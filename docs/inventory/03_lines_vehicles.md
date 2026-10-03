# 03: Line and vehicle management (LVM)

Scope: `game/gui/gui/line_vehicle_mgmt/` (all paths below are relative to that directory unless prefixed).
Main files: `manager_window.tl` (8564 lines, the "Line Manager" tool window), `line_manager_panel.tl` (stop list),
`cargofilter_window.tl` ("Configure Stop" popover), `vehicle_store_window.tl` / `vehicle_store_table.tl` /
`vehicle_store_util.tl` (buy/replace/modify store), `vehicle_list_react_util.tl` (vehicle list),
`line_react_util.tl`, `line_util.tl`, `manager_hud_util.tl` (in-world HUD while LVM is open),
`auto_rename/`, `first_stop_to_send/`.

Click counting conventions: "1" = one click / key press. "Open LVM" = 1 (key L = `IA_MANAGEMENT_MODE`,
`SCR/settings_keys_v3.lua:332`, or game-bar button `game_bar/game_bar.tl:765-773`). Typing a search string is
counted as 1 click (focus) + typing.

## 1. Surfaces

### 1.1 Line Manager tool window ("LVM"): `ManagerToolWindow` (manager_window.tl:8214), content `ManagerWindowContent` (5896)
- Purpose: single combined window: line+depot list (top), vehicle list (middle), selected line/depot panel (bottom), plus an in-world "action mode" that changes what clicking the map does.
- Entry points (all fire event `openVehicleManager`, handled at manager_window.tl:8447):
  - Key L / game-bar "Line Manager" button (`game_bar.tl:580-585`, toggles; `hideFn` fires `closeVehicleManager`).
  - Line entity window → primary button "Manage Line" (`entity_window/line/line.tl:141-148`) → opens with that line selected, SEGMENT mode at last stop, all line vehicles in vehicle list (manager_window.tl:7947-7965).
  - Vehicle entity window → "Send to Line" (`entity_window/vehicle/vehicle.tl:396-405`) → opens with that vehicle + Send-to-Line popover open (7875-7934).
  - Clicking a depot in the world (outside LVM): `entity_window/view_manager.tl:556-563` opens the LVM instead of a depot window (depot + its vehicles selected; if empty depot → vehicle store opens directly, 7977-7988).
  - Maintenance station window → "Manage Vehicles" (`entity_window/maintenance_station/maintenance_station.tl:88-94`).
  - Statistics → Lines tab "Vehicles" cell click (`statistics/statistic_lines.tl:45-53`), Depots tab (`statistic_depots.tl:37`).
- Closing: window close button (`closable = true`, 8218), L again, `closeVehicleManager`. It is a tool on the tool stack (`react.RegisterTool{name="Manager"}`, 8313) → it can be shelved/hidden when another tool is pushed (8327-8334). Closing removes vehicle-store, popovers and cargo-filter windows (8286-8294, 8320-8325).
- Selection is not remembered between openings: `rememberSelection = false` (8445) → every open starts with empty line and vehicle selection and MAIN mode (8464-8468).
- Map rendering while open: a dedicated LineVehicleColor layer, all player lines drawn (or only the filtered/selected ones) (`line_util.tl:1023-1060`, manager_window.tl:411-433).
- Layout (8193-8205): TopBar → LineManager → VehicleManager → LinePanel (+ FeedbackList overlay for confirmations/errors, 8178-8189).
- Code facts: no `ExtensionPoint`/`usePlugins` anywhere in `line_vehicle_mgmt/` (grep). Exported recipes only: `ManagerEntryPoint`, `ManagerTool`, `ManagerToolWindow`, `ManagerWindowContent` (manager_window.d.tl:173-177). All sub-recipes (LineAndDepotList, LineAndDepotListEntry, VehicleManagerActionButtons, LinePanel*, SendToLineSelection, AutoRenameDialog, LineStatisticDetails…) are file-`local`. Update cadence: most data via `useStepState`/`useStepStateTimer` (per frame / timer). Problem cache recomputes 4 lines per frame + one system query every 3 frames (5956-6061).

#### Internal "LVM modes" (what a world click does): `switchLVMMode` (6068), action fns 7429-7449
| Mode | Set by | World-click behaviour |
|---|---|---|
| MAIN (230) | default / no single line selected | click line → select line (+all its vehicles); click station → create new line starting there (304-318); click depot → add/remove its vehicles to list, or open vehicle store if empty (334-358); click vehicle → add to list / toggle selection (182-228); warehouse → open its window |
| SEGMENT (456) | single line selected | click station → insert stop after current segment (653-673, 6767-6790); click line → choose segment (598-610); click depot → open store for depot and line (purchases auto-assigned) (678-693); click road/track → add waypoint only while holding `IA_PRECISION_MODE` modifier (default prefers stops, 535-562, 694-715); click waypoint → move waypoint |
| MOVE_STOP (838) | "Move Stop" button | click station → re-target the stop (6851-6868); Esc cancels (884-895) |
| MOVE_WAYPOINT (1013) | "Move Waypoint" | click location → move waypoint |
| SEND_TO_LINE (1178) | "Send to Line" button | click line on map → send selected vehicles; click depot → send to depot; click station → create new line and send vehicles to it (1242-1285). Non-compatible lines are dimmed, hovered line in popover is highlighted (1296-1306) |

`Esc` (`IA_MENU_BACK`) in mouse mode: deselect all lines (and clear vehicle list) or cancel "creating new line" (7451-7488).

### 1.2 Top bar: `LineVehicleManagerTopBar` (5742)
- Status: none (mode/buffer debug displays are hard-disabled: `showLvmMode=false`, 5781-5827).
- Actions: search field (5842-5852). It filters the line/depot list by line name, depot name or cargo name carried by the line (2547-2562).

### 1.3 Line manager section: `LineManager` (2847) = `LineManagerActionButtons` (1575) + `LineAndDepotList` (2463)
Action bar (1575-1841):
- Master tri-state checkbox "select all lines+depots" (1635-1749): selects all (filtered) lines and depots and loads every vehicle of those lines/depots into the vehicle list; second click clears. Badge = number of lines with problems; tooltip "{count} Lines With Problems" (1507-1564).
- Carrier category filter (Road/Tram/Rail/Ship/Air toggles) (1775-1791, categories 2489-2515).
- "New Line" button (1803-1831) → clears selection, sets `creatingNewLineState`, shows InfoBox "Creating New Line – Add stations by selecting them in the world" with Cancel (4426-4434, 7296-7304). Optional: in MAIN mode a click on any station already creates a line.

Line/Depot list (`builtin.DataTable`, 2746-2756): one column "Name", `disableSortKey = true` (2722-2747) → fixed order (lines first, then depots, by name); keyboard navigation on.
Row recipe `LineAndDepotListEntry` (1957-2461). Status visible per line row without clicks:
- checkbox with badge = number of vehicles with problems on that line (`ToggleSelectLine`, 1851-1916; tooltip "N Vehicles With Problems").
- line colour dot (`line_react_util.ColorWidget`; click = open Line entity window, 2154-2164).
- name, rendered with class `problem` (red) when the line has stop/path problems or a `LineIssue` (2088, 2131-2140, 6008-6013).
- `line_react_util.ManagerNotificationWidget(entity)`: icons of persisting notifications for that entity (line_react_util.tl:107-140).
- Not shown: carrier/vehicle type, vehicle count, frequency, utilization, balance/profit, cargo.
- Hover-only buttons (`hidden-button` unless hovered, 2190, 2206, 2270): Rename (inline edit), Locate, Delete line (confirm via feedback "Deleting the line will sell all vehicles on the line." only if vehicles>0; 2281-2295).
- Row click = select only this line (override selection) + replace vehicle list with the line's vehicles (all selected) + SEGMENT mode at last stop (1387-1411, 2614-2653). Double-click = camera follow. Checkbox click = add/remove line to multi-selection (and its vehicles).
Depot rows: checkbox, depot icon (opens depot window), name (grey if empty), notifications, hover: Rename, Locate, "Buy Vehicles In Depot" (cart) (2297-2413).
Empty state: "No lines or depots exist." (2877-2891).

### 1.4 Vehicle manager section: `VehicleManager` (5402) = `VehicleManagerActionButtons` (4864) + `VehicleList`
The vehicle list is not "all vehicles"; it is a working set filled by selecting lines/depots or clicking vehicles in the world. Empty state "Select a vehicle, depot or line." (5704-5724).

Action bar (all act on selected vehicles; tooltips switch to "… All Vehicles" when all are selected):
| Control | Code | Behaviour / confirmation |
|---|---|---|
| master checkbox + problem badge | 4934-4971 | select all / none; tooltip "{count} Vehicles With Problems" |
| Reverse | 4984-4998 | immediate, no confirm |
| Start/Stop | 5000-5046 | toggles `userStopped`, no confirm |
| Colour (palette) | 5048-5082 | sets vehicle colour (skips models without colour mask) |
| Clone | 5092-5123 → event `duplicateVehicles` (8494-8561) | buys an identical copy of every selected vehicle, sends to "best line & depot" (`findBestLineAndDepotForVehicle`), no confirmation |
| Replace (toggle) | 5167-5223 | opens Vehicle Store in Replace mode for the selection; disabled unless all selected share one carrier (and not planes+helicopters mixed) |
| Modify (toggle) | 5225-5279 | rail/tram only; Vehicle Store in Modify mode (edit consist) |
| Send to Depot | 5289-5314 | `makeVehicleSendToDepotCmd(entity, false)` per vehicle, no confirm, engine picks depot; `sellOnArrival`/`jumpToDepotEntity` API params never used (apidef cmd.d.tl:915) |
| Sell | 5316-5356 | inline feedback question → Accept; refuses if any protected |
| Send to Line (primary) | `SendToLineButton` 4792-4848, handler 7311-7377 | opens popover "Send To Line" + switches to SEND_TO_LINE world mode |

Vehicle list: `vehicle_list_react_util.VehicleList` (vehicle_list_react_util.tl:525-605), `DataTable` with `disableSortKey = true` (594), initial sort by column 2 ("line"):
| Column | Shows | Click |
|---|---|---|
| ToggleSelectVehicle (25) | checkbox | toggle selection |
| VehicleLineSmall (125) | colour square of the line, or depot icon ("Going to {depot}" / in depot) via `LineOrDepotButton` (line_react_util.tl:471) | select that line (and scroll to it) |
| VehicleName (203) | name, red if vehicle has a problem (245-252, 319) ; hover: Rename | select |
| VehicleIcon (375) | model icon (opens Vehicle entity window), notifications, hover: Locate, "Remove Vehicle From List" | |
- Not shown: age, condition (`vehicle_react_util.ConditionIcon` exists but is commented out, vehicle_list_react_util.tl:456), balance, load, current status (stuck/blocked reason), speed, model name.
- Bug: sort compare value for column 2 overwrites the line name (`firstPart = … and "Going to Depot" or "In Depot"`, vehicle_list_react_util.tl:541-545) → initial "line" sort effectively groups by depot-status, not by line.

### 1.5 Line panel: `LinePanel` (4230)
Shown content depends on selection (4253-4387):
- 0 lines/depots: placeholder "Select a line or depot." + disabled "Buy Vehicles".
- exactly 1 line: `LinePanelActionButtons` (3447) + stop list `LineManagerPanel` + stat strip `LineStatisticDetails` (3830).
- exactly 1 depot: `LinePanelDepotActionButtons` (3323): Buy Vehicles + depot name/rename.
- several: action buttons for the set + `LineStatisticDetailsList` (4148), one stat strip per selected line/depot, DataTable with `disableSortKey = true` (4205-4213).

LinePanelActionButtons (3447-3721): Auto-Rename (wand → popover `AutoRenameDialog`), Line colour palette (multi-line → confirm "Set color for multiple lines?", 3604-3638), "Buy Vehicles" (3644-3679; enabled only with exactly 1 line or depot, 7378-7390). Name header with LineCargoDisplay (cargo icons) + hover rename (2960-3078).

Stat strip `LineStatisticDetails` (3939-4012), always visible for the selected line: Capacity, Utilization, Frequency (interval mm:ss, `line_util.calculateFrequencySeconds`), Rate (per year), Balance (annual, coloured).

### 1.6 Stop list (line editor): `LineManagerPanel` (line_manager_panel.tl:1327-1923), row `LineStopItem` (631-1148)
- Vertical line diagram in line colour; per stop: number bubble, name (inline rename), cargo icons (`LineCargoDisplay` with configure toggle), problem markers on segments (red segment + alert icon with tooltip text, only first problem per stop: 1779, 1820).
- After the selected stop a ghost row `LineStopItemPreview` ("Add the next stop here by selecting a station in the world", 1150-1315) = insertion point.
- Hover-only buttons (`showButtons = hovered`, 770-784): Rename stop, Locate, Configure Stop (opens CargoFilterWindow), Move Stop (→ MOVE_STOP 3D mode), Select Terminals (popover), Remove Stop/Waypoint (no confirmation; removing last stop deletes the line if no vehicles, manager_window.tl:6791-6850).
- Row click = select segment (insert point); double click = camera to stop. Drag handle = reorder via DnD (`LineDragHandle` 524, drop → `moveVia` 680-712).
- Vehicle positions along the diagram: implemented but commented out (1396-1438, 1857-1871) → no bunching/distribution view.
- Each edit is committed immediately as a `makeLineUpdateCmd` (manager_window.tl:6435-6570); there is no draft/apply.

Terminal selection popover `TerminalSelection` (107-520): per terminal: number, type (Passenger / cargo class), length, overlength warning "Terminal is too short for some vehicles." (435), path problem markers, ComboBox Don't Use / Alternative / Preferred (288-316).

### 1.7 Configure Stop window: `CargoFilterWindow` (cargofilter_window.tl:886-911), content `CargoFilterContent` (277-884)
- Opened from: stop row cargo icons/"Configure Stop" button (line_manager_panel.tl:915-988) or HUD stop row in world (manager_hud_util.tl:216-282). Singleton, positioned next to row, not movable, no close button (`closable=false`, 897-899); closes by toggling the button or Esc (563-569).
- Title "#{n} - {station}".
- Load card: icons of cargo types loaded at this stop with fill-level %; "+" "Select Cargo to Load" → grid of currently-produced cargos (catchment ones highlighted) + Fill Level slider; per-icon "x" remove; info "Cargo can only be (un)loaded at this stop"; checkboxes Force Unload All Cargo On Arrival, Destroy Cargo On Arrival When Config Changes, Replace with Newer Cargo if Available (745-787).
- Departure Configuration card: loading mode toggle group Load if Available / Full Load (Any) / Full Load (All) (795-824); sliders + click-to-type spin boxes: Max. Additional Wait, Min. Stop Time, Max. Stop Time (0-600 s, "---" = unlimited) (826-873).
- Any change sets `lineData.customFilters = true` (438) which permanently disables automatic cargo configuration for the whole line (`line_util.autoLoadConfig` returns early, line_util.tl:495-498). No UI indicator and no "reset to automatic".
- Per stop only: no copy/apply-to-all-stops.
- There is no line-level frequency/interval/timetable setting anywhere in LVM; "Frequency" is display-only. Reservation priority exists only in the Line entity window (`entity_window/line/line.tl:150-156`).

### 1.8 Send-to-Line popover: `SendToLineSelection` (4513-4686)
- PopoverWindow anchored at the vehicle action bar; header: "only visible lines" toggle, title, ComboBox "Stop To Send Vehicles To" = first-stop-to-send scheme (4596-4615); body: alphabetical list of compatible lines (colour dot + name) (4522-4544); hover highlights the line on the map.
- Click line → `makeVehicleSetLineCmd` per vehicle with stop index from scheme (4688-4763); failure → feedback "Vehicles could not be assigned to line. Missing electric tracks…" (5407-5427).
- No info per line in the list (vehicle count, carrier, frequency).

### 1.9 Auto-Rename popover: `AutoRenameDialog` (3090-3307)
- Opened by wand button (3520-3571). Lists every `rename_scheme` resource as a big button with a live preview of the first 3 new names (+N more). One click renames all selected lines.
- Schemes shipped: "First Stop - Last Stop", "Town - Cargo", "Town - Carrier" (`auto_rename/schemes/*.res.lua`); components firststop/laststop/town/cargo/carrier (`auto_rename/scheme_components/*`). Loaded from `api.res.genericRep.getAllOfType("rename_scheme")` (8356-8390) → data-moddable.
- Default line name on creation: "Line {n}" (`line_util.makeLineName`, line_util.tl:66-85); colour: least-used palette colour (38-64). Auto-rename is never applied automatically.

### 1.10 First-stop-to-send schemes (`first_stop_to_send/`)
- Resources of type `firstStopToSend_scheme` (8392-8411): Evenly Distributed, First Cargo Compatible Stop, First Stop, Next Reachable Stop.
- Default per carrier hard-coded in a `useRef` (8414-8435): Road/Air/Water passengers = evenlydistributed, cargo = firststop; Rail/Tram = nextreachable. Changing the combo in the popover updates this map for the session only (4601-4611; not saved).
- Used for: Send to Line, buying with a line selected, cloning, sending to a new line (`getSendScheme` 4474-4502).

### 1.11 Vehicle Store window: `VehicleStoreWindow` (vehicle_store_window.tl:4580-4678), entry `VehicleStoreEntryPoint` (4680)
- Modes: Buy / Replace / Modify, via events `buyVehicles` (4870), `replaceVehicles` (4895), `modifyVehicles` (4932). Only one store window at a time (`removeAllWindows` before add).
- Entry points (Buy): LVM "Buy Vehicles" with 1 line (auto-chooses depot via `line_util.getBestDepotForLine`, manager_window.tl:7391-7411; warning "Cannot find suitable depot reachable from the line.") or 1 depot; depot row cart button; click depot in world in SEGMENT mode (line+depot) or empty depot in MAIN mode; empty depot clicked outside LVM. Title "Buy Vehicles At {depot}" with Locate button.
- Replace/Modify: LVM action bar toggles or Vehicle entity window "Replace"/"Modify" (`entity_window/vehicle/vehicle.tl:448-500`).
- Layout: TopBar (search field as tab 0 + for rail tabs Locomotive/Wagon/Multiple Unit, tram Railcar/Locomotive/Wagon (2471-2498); layout toggle "Table Layout" (2403-2423)); MidBar (engine filter Steam/Diesel/Electric for rail/tram (2164-2235), size filter for air/water, light-rail filter for tram, Compare toggle (only in Replace when all replaced vehicles are identical, 2868-2888), SortOptions (2010-2128)); cargo-type filter bar; list; details pane; cart/bottom bar.
- Default sort = "Year of Availability", ascending (2550-2554) → oldest model first; default selected element = index 1 (2541-2544) → bottom "Buy" button immediately targets the oldest model.
- Sort modes: Name, Year, Capacity, Speed, Power/Thrust, Noise, Pollution, Load Speed, Comfort, Running Costs, Weight, Length, Cost (2019-2075). Table layout: sortable DataTable columns incl. price (vehicle_store_table.tl:347-480, 574-582); each row has its own buy/add button (300-336).
- Only currently available models are listed (year filter, vehicle_store_util.tl:720-736) + game vehicle filter.
- Road/air/water ("buyImmediately", no cart): select model → bottom button "Buy {count} Vehicles for {cost}" + spinbox 1-99 (4290-4341). `onActivate` on a list item buys 1 immediately (1527-1562; trigger = double click/Enter; needs in-game verification).
- Rail/tram (cart): per-model cart button adds part/MU to the consist (858-898); cart shows each consist with drag&drop reorder (`VehicleCartDnd` 3058), per-part Reverse/Remove (3364-3374), stats (running costs, capacity, length, speed, performance), delete consist; amount spinbox only for the first cart entry (4342-4356); "Composition has no vehicle with engine." error (4254).
- Replace mode: all selected vehicles are replaced with the same new config (4183-4203 / 4055-4061); "Vehicles To Replace:" widget (3959-3969); price is per vehicle × count; Compare shows old vs new stats (`CompositionComparisonDetails` 707).
- Modify mode: initial cart = current consists of each selected train (4493-4532); per-train checkboxes choose which trains receive added parts (3865-3873, 4080).
- On accept: `vehicle_react_util.HandleVehicleChanges` (vehicle_react_util.tl:319-412): buy (`makeVehicleBuyCmd` at depot, or best depot if none) then `makeVehicleSetLineCmd` to the line with first-stop scheme; replace via `makeVehicleReplaceCmd`; empty config = sell.
- Purchased vehicles are added to the LVM vehicle list and, when the store was opened for a line, sent to it (manager_window.tl:7154-7184).

### 1.12 In-world HUD while LVM is open: `manager_hud_util.LineVehicleManagerHudIconMaster` (manager_hud_util.tl:908-1418)
- Stations: line dots for each line serving the station (click = select line, 124-167); when a line is selected, per-stop rows with stop number (click = select segment), cargo icons (click = Configure Stop), hover: Configure/Move/Remove stop (189-379); alternative terminal add/remove buttons (640-700).
- Depots: mini vehicle widgets for vehicles in the depot, click = add/select in list (1327-1396).
- Industries/towns: cargo input/output indicators (only in SEGMENT etc., suppressed in MAIN, 998-1083).
- Waypoints: move/remove (732-905).

### 1.13 Feedback list (inline confirmations): `feedback_list_util.FeedbackList` (feedback_list_util.tl)
Used instead of modal dialogs: Question items with Accept/Cancel, Info/Warning/Error with Dismiss; default timeout 5 s (feedback_list_util.tl:114-144; whether questions time out → needs in-game verification).

## 2. Task flows (click counts from code)

F1. Create a new bus line with 4 stops and 3 buses
1. Open LVM (1).
2. Click station A in the world (1) → line "Line N" created with auto colour, SEGMENT mode (manager_window.tl:304-318, 6691-6715, 6472-6478).
3. Click stations B, C, D (3) → each inserted after the previous (6767-6790); terminals auto-assigned (`autoAssignTerminals`), cargo auto-configured (`autoLoadConfig`).
4. "Buy Vehicles" (1) → store for auto-chosen depot.
5. Select bus model (1) (default selection = oldest model), spinbox to 3 (2 clicks on arrow or click+type), "Buy 3 Vehicles for …" (1).
6. Vehicles auto-sent to the line, evenly distributed over stops (scheme map 8415-8418).
- Total ≈ 10 actions, 2 windows (LVM + store). Close store (+1). Alternative: "New Line" button first (+1, no benefit). Alternative to steps 4-5: click a depot in the world (SEGMENT mode) to pick a specific depot (1) instead of "Buy Vehicles".

F2. Add N vehicles of the same model to an existing line
- Path A (store): open LVM (1) → find line (scroll or search: 1 + typing) → click line (1) → Buy Vehicles (1) → select model (1) → spinbox (N-1) → Buy (1) ⇒ 5 + N-1 (+search).
- Path B (clone): open LVM (1) → click line (1, selects all its vehicles) → master checkbox to deselect all (1) → tick one vehicle (1) → Clone (1) ⇒ 5 per vehicle, no store. Danger: pressing Clone right after selecting the line duplicates the whole fleet without confirmation (5092-5123).
- Path C (from world): click line in world → Line entity window → "Manage Line" (1) → continue as A (saves the search).

F3. Replace all (old) vehicles of a line with a new model
- All vehicles: open LVM (1) → line (1+find) → Replace (1) → pick model (1, list filtered to compatible transport modes/filter tags) → "Replace N Vehicles for X" (1) ⇒ 5. For trains: replace step becomes composing the consist in the cart (≥1 click per loco/wagon, drag to reorder) then Replace.
- Only old ones: LVM shows no age/condition → user must open each vehicle window (≥2 clicks each) or open the Statistics → Vehicles tab (sortable Age/Condition, `statistics/statistic_vehicles.tl:368-369`) and then hand-select vehicles in LVM one by one (1 per vehicle). Realistically 5 + 2·N clicks and 2–3 context switches.
- Mixed carriers in selection disable Replace (5167-5169).

F4. Find lines that lose money
- In LVM: list shows no balance. Options: click each line and read Balance in the stat strip (1 click per line), or master checkbox (1) → `LineStatisticDetailsList` lists every line's strip (unsortable) and loads every vehicle of every line into the vehicle list.
- Alternative: Statistics window → Lines tab → click "Balance" header (sortable, statistic_lines.tl:414) ≈ 3 clicks, then "Vehicles" cell (1) opens LVM on that line.
- Line-level "why" (empty runs, nowhere to unload) is computed (`getLinesIssues`, 6056) but only rendered as a red name; the issue type is never shown in LVM.

F5. Find vehicles that are old / broken / stuck
- Stuck/no-path: red vehicle name + badge count on line checkbox and on master checkbox; tooltip only gives the count (1507-1535, 1861-1916). The reason (`VehicleProblem`: NoPathElectric/Ship/Aircraft/Generic, Blocked; apidef type.d.tl:2158-2164) is not displayed → open vehicle window per vehicle.
- Old / low condition: not available in LVM → Statistics Vehicles tab (sort Age/Condition) or each vehicle window.

F6. Change a line's stops
- Append stop: select line (1) → click station (1) ⇒ 2.
- Insert between stop k and k+1: select line (1) → click stop row k or the segment in the world (1) → click station (1) ⇒ 3.
- Remove stop: select line (1) → hover row → trash (1) ⇒ 2 (no confirm, no undo).
- Move stop to another station: select line (1) → hover → Move (1) → click station (1) ⇒ 3.
- Reorder: drag handle (1 drag).
- Change terminal: hover → Select Terminals (1) → combobox (2) ⇒ 3 + select line.
- Waypoint: hold precision modifier + click track (1).
- Every change is an immediate `LineUpdateCmd`; vehicles may reroute immediately.

F7. Rebalance N vehicles from line A to line B
- Open LVM (1) → click A (1, all its vehicles selected) → master checkbox to deselect (1) → tick N vehicles (N) → Send to Line (1) → find B in alphabetical popover list (scroll) and click (1) ⇒ N + 5.
- Alternative after Send to Line: click line B on the map (SEND_TO_LINE mode) instead of the popover.
- No info about which line is over/under-served while choosing (no vehicle counts/utilization in popover).

F8. Set cargo for a truck line
- Default: automatic per stop from catchment supply/demand (line_util.tl:495+), 0 clicks.
- Manual per stop: select line (1) → hover stop → Configure Stop (1) → "+" (1) → pick cargo (1) [→ optional fill-level slider] ⇒ 4 per stop; 2-stop line ≈ 8. Loading mode "Full Load" per stop: +1. Waiting times: +1-2 per slider.
- Side effect: first manual change turns off auto-config for the whole line forever (no indicator, no reset).

F9. Send vehicles to depot / sell
- Send to depot: select vehicles (≥1) → depot icon (1), engine chooses depot, no confirm. Clicking a specific depot in SEND_TO_LINE mode shows "Send to {depot}" tooltip but `sendVehiclesToDepot(selection, __depotEntity)` ignores the depot (5595-5605) → needs in-game verification; likely always nearest depot.
- Sell: select (≥1) → Sell (1) → Accept (1). Selling a line's whole fleet = select line (1) + Sell (1) + Accept (1).
- "Send to depot and sell on arrival" / "renew on arrival": API supports `sellOnArrival` (cmd.d.tl:915) but no UI.

F10. Rename / recolour / auto-rename lines
- Rename: hover row → pencil (1) → type → Enter (1).
- Auto-rename: select lines (1 or master checkbox) → wand (1) → scheme (1) ⇒ 3 for any number of lines.
- Colour: palette (1) → colour (1) (+1 confirm for multiple lines).

F11. Delete a line: hover row → trash (1) → Accept (1) when it has vehicles (vehicles are sold). With no vehicles: 1 click, no confirm.

F12. Stop/start all vehicles of a line: select line (1) → Start/Stop (1).

F13. Buy trains with a custom composition (rail): line (1) → Buy Vehicles (1) → Locomotive tab (default) pick loco cart button (1) → Wagon tab (1) → wagon cart button ×k (k) → amount spinbox (if >1) → Buy (1) ⇒ ≈ 5 + k. Platform length check is only visible later in Select Terminals popover ("Terminal is too short", line_manager_panel.tl:435).

## 3. Friction findings

| # | Finding | Evidence | Impact |
|---|---|---|---|
| 1 | Line list has a single "Name" column, sorting disabled; no carrier, vehicle count, frequency, utilization or balance per line → no at-a-glance health of the network. | manager_window.tl:2722-2756 (`disableSortKey = true`), row 1957-2461 | High |
| 2 | Vehicle list shows no age, condition, balance, load or problem reason; `ConditionIcon` commented out; not sortable. Replacing "old" vehicles requires the Statistics window or per-vehicle windows. | vehicle_list_react_util.tl:456, 525-605 | High |
| 3 | Problems are a red colour + count only. Line issue type (`NowhereToLoad`, `NowhereToUnload`, `VehicleUseless`, `LineCargoConfig`…) and vehicle problem type (`Blocked`, `NoPathElectric`…) are computed but never shown. | manager_window.tl:6008-6056; apidef type.d.tl:2158, 5716 | High |
| 4 | Selecting a line auto-selects all its vehicles; destructive/bulk actions (Clone, Sell, Replace, Send) then target the whole fleet. Clone has no confirmation → one misclick doubles a line's fleet. | 1387-1411, 5092-5123 | High |
| 5 | Multi-line statistics view (`LineStatisticDetailsList`) unsortable and coupled with loading every vehicle into the vehicle list. | 4148-4216, 1699-1745 | Med |
| 6 | Selection/mode not remembered when LVM is closed and reopened (`rememberSelection=false`). Re-finding a line each time. | 8445-8468 | Med |
| 7 | Vehicle store defaults to "Year of Availability ascending" and pre-selects the first (oldest) model; bottom Buy button immediately offers to buy it. | vehicle_store_window.tl:2541-2554, 2740-2764, 4241-4248 | Med |
| 8 | Configure-Stop is per stop only (no "apply to all stops", no line-level loading mode/wait time); any edit silently disables auto cargo config for the entire line with no indicator/reset. | cargofilter_window.tl:394-445, line_util.tl:495-498 | Med-High |
| 9 | No frequency/interval target or timetable; frequency only displayed; no suggestion of "vehicles needed". | 3973-3987 | Med (feature gap; engine-level for real timetables) |
| 10 | Vehicle distribution along the stop diagram (bunching) is implemented but commented out. | line_manager_panel.tl:1396-1438, 1857-1871 | Med |
| 11 | Send-to-Line popover: plain alphabetical name list, no carrier/vehicle-count/utilization, scheme choice not persisted. | 4513-4686, 8414-8435 | Med |
| 12 | Send to depot ignores the depot clicked in SEND_TO_LINE mode (tooltip promises it); no "sell on arrival" option although API supports it. | 5595-5605, cmd.d.tl:915 | Med (needs in-game verification) |
| 13 | Most row actions (rename, locate, delete, configure, move, terminals, remove stop) are hover-only; nothing discoverable without hovering; remove stop has no confirm/undo. | 2190-2296, line_manager_panel.tl:770-784, 1053-1072 | Med |
| 14 | No keyboard shortcuts for vehicle actions in mouse mode (only Esc = deselect); gamepad has a full mapping (6259-6279, 7590-7686). | 7451-7488 | Low-Med |
| 15 | Vehicle list "line" sort compare bug → grouping by depot status instead of line. | vehicle_list_react_util.tl:541-545 | Low |
| 16 | Overlength (train longer than platform) only visible in Select Terminals popover. | line_manager_panel.tl:156-169, 435 | Med (rail) |
| 17 | Rebalancing requires manual deselect-all then N ticks; no "move k vehicles" or drag vehicle onto line. | 4934-4966 | Med |
| 18 | Buy Vehicles disabled for multi-line selection; buying for several lines = repeat whole flow per line. | 7378-7390 | Low-Med |
| 19 | Store amount spinbox max 99, only first cart entry in rail cart has an amount. | vehicle_store_window.tl:4329-4356 | Low |
| 20 | Configure-Stop window cannot be moved and has no close button. | cargofilter_window.tl:893-899 | Low |
| 21 | Reservation priority only in Line entity window, not in LVM. | entity_window/line/line.tl:150-156 | Low |

## 4. Improvement opportunities

Moddability primitives (evidence):
- Data extension (easy): `rename_scheme`, `rename_scheme_component`, `firstStopToSend_scheme` generic resources (manager_window.tl:8356-8411).
- Recipe replacement (medium): `react-replacement-config` resources → `ReplaceRecipe(original, replacement)` before init (`main/bootstrap_game.tl:6-50`, `main/react.lua:445-455`). Only works on recipe functions the mod can reference = exported ones: `manager_window.{ManagerEntryPoint, ManagerToolWindow, ManagerWindowContent}`, `vehicle_list_react_util.VehicleList`, module returns of `line_manager_panel.tl` and `cargofilter_window.tl`, `vehicle_store_window.{VehicleStoreWindow, VehicleStoreEntryPoint}`, `manager_hud_util.LineVehicleManagerHudIconMaster`, `manager_tooltips_util.*`, all `line_react_util.*` and `vehicle_react_util.*`. `CallOriginalRecipe` allows wrapping.
- Local (non-exported) recipes (LineAndDepotList/Entry, VehicleManagerActionButtons, LinePanel*, SendToLineSelection, VehicleStoreBrowser, VehicleCart…) can only be changed by replacing an exported ancestor with a forked copy (e.g. replace `ManagerWindowContent` with a copy of the whole file) → hard / high maintenance (or file override; needs verification).
- Injection trick: `line_react_util.ManagerNotificationWidget(entity)` is rendered inside every line row, depot row and vehicle row (manager_window.tl:2186, 2347; vehicle_list_react_util.tl:493). Replacing this exported recipe (wrap original via `CallOriginalRecipe`) lets a mod add per-row badges/buttons without forking the LVM → medium-easy, and it reaches every row. Similarly `line_react_util.ColorWidget` (line rows) and `LineOrDepotButton` (vehicle rows).
- New standalone windows: own recipes + a game-bar/mod-button entry (`main/main_mod_button_area.tl:7` `MainModButtonAreaExtension`) → easy; can fire `openVehicleManager` with `openWithLineEntity`/`openWithVehicleEntities`/`sendToLineMode` to jump into LVM.

| # | Proposal | Saving | Moddability |
|---|---|---|---|
| I1 | Per-line status badges in the line list: carrier icon, vehicle count, utilization %, annual balance (red if <0), issue icon with reason tooltip (from `getLinesIssues` / `getDetailedLineProblems`). | Find losing/broken lines: N clicks (one per line) or ~4 clicks + window switch → 0 clicks (scan) | Replace `line_react_util.ManagerNotificationWidget` (exported) and branch on `LINE` component → medium-easy. Data APIs exist: `LineBalance`, `calcLineStationThroughput`, `getMaxFrequency`, `statistics_react_util.calculateCargoColumnDataForLine`. |
| I2 | Sortable/filterable line list (by balance, utilization, problems, vehicle count) + "show only lines with problems / losses" filter. | 1 click to get worst line on top vs. N | List is local `LineAndDepotList` with `disableSortKey=true` → fork `ManagerWindowContent` (hard) or standalone "Line Overview" window that opens LVM on click (easy). |
| I3 | Vehicle row badges: age (years / % of lifespan), condition icon, problem reason (`VehicleProblem`), "stopped", annual balance. | Replace-old flow 5+2N → 5+N (or 0 lookups) | Same `ManagerNotificationWidget` injection for TRANSPORT_VEHICLE entities; helpers exist: `vehicle_util.getAge`, `getAvgMaintenanceState`, `vehicle_react_util.ConditionIcon`, `VehicleBalance` → medium-easy. |
| I4 | Sortable vehicle list + "select old/worn/problem vehicles" quick buttons (e.g. "select vehicles older than lifespan", "select problem vehicles"). | Old-vehicle selection N clicks → 1 | `vehicle_list_react_util.VehicleList` is exported → replace with own version (add columns, `disableSortKey=false`); the selection API is reachable via `params.managerRef:getApi().selectVehicles` → medium. Quick buttons need action bar (local) → put them in the replaced VehicleList header → medium. |
| I5 | Safer selection semantics: when clicking a line, show vehicles but select none (or require confirm for Clone/Sell when > k vehicles). | Avoids accidental fleet duplication; rebalancing N+5 → N+4 | Selection logic in local `selectSingleLineAndOverrideSelectionOnClick` → fork (hard). Cheaper: replace event handler? `duplicateVehicles` is handled in exported `ManagerEntryPoint` → wrap/replace ManagerEntryPoint to add a confirm when >1 vehicle → medium. |
| I6 | Remember LVM selection/mode across reopen (flip `rememberSelection`). | Re-finding line: 1-3 clicks/typing per reopen → 0 | Local constant inside exported `ManagerEntryPoint` → replace ManagerEntryPoint with copy (≈225 lines, 8337-8562) → medium. |
| I7 | Store defaults: sort by year descending, preselect newest/best-fit model, remember last chosen model per carrier/line. | Buy flow: avoids scroll + prevents wrong buy; −1-3 clicks | Defaults in local `VehicleStoreBrowser` (2537-2554) → replace exported `VehicleStoreWindow` with fork (hard-ish, ~2.5k lines involved). |
| I8 | "Add 1 more like this" button per line (clone the line's most common/newest vehicle into the same line). | F2: 5+N-1 → 2 + (N-1) | Line-row injection via ManagerNotificationWidget + fire `duplicateVehicles` event with `{vehicleEntities={v}}` (8494) → easy-medium. |
| I9 | Line-level stop config: "apply this stop's loading mode / wait times to all stops", "reset cargo to automatic" (clear `customFilters`). Show an "auto/manual cargo" indicator. | Full-load on all stops of k-stop line: 2k+1 → 3 | `CargoFilterWindow` is module-exported → replace with extended version (fork 913 lines) → medium; commands via `api.cmd.makeLineUpdateCmd` (pattern at cargofilter_window.tl:394-445). |
| I10 | Frequency helper: show "target interval → vehicles needed" and +/- buttons that clone/send-to-depot vehicles. | Manual trial-and-error → 1 click per step | Injection widget + `duplicateVehicles` / `makeVehicleSendToDepotCmd(v, true)` → medium. True timetables = engine (not feasible). |
| I11 | Re-enable vehicle positions on the stop diagram (bunching view). | Status at a glance | Commented code in `LineManagerPanel` (exported module return) → replace with fork that uncomments → medium. |
| I12 | Send-to-Line popover with line metadata (carrier, vehicle count, utilization, frequency) + persist chosen first-stop scheme. | Faster target choice; less map-hovering | `SendToLineSelection` local → fork (hard). Persisting scheme: replace `ManagerEntryPoint` (medium). New schemes via `firstStopToSend_scheme` res (easy). |
| I13 | "Send to depot & sell on arrival" and "renew" (replace with same model when arriving) buttons; honour clicked depot via `jumpToDepotEntity`. | Renew old vehicles without stranding: today Sell (loses positions) or Replace (instant); +0-1 click | Vehicle-row injection (per-vehicle) easy-medium; action-bar button requires fork of `VehicleManagerActionButtons` (hard). API: `makeVehicleSendToDepotCmd(entity, sellOnArrival, jumpToDepotEntity)`. Renew-on-arrival needs a game script/polling; needs verification. |
| I14 | Rebalance helper: per-line "move k vehicles to…" or drag a vehicle row onto a line row. | F7: N+5 → 3 | Drag source/target rows are local → fork (hard); a standalone "Rebalance" window using `makeVehicleSetLineCmd` (easy). |
| I15 | Mouse hotkeys in LVM (Del = sell/delete with confirm, D = send to depot, C = clone, R = replace, Ctrl+A select all vehicles). | 1 click + mouse travel → 1 key | Input actions in exported `ManagerWindowContent` / new IA definitions → replace ManagerWindowContent (hard) or add `useInputAction` in an injected always-mounted widget that calls `vehicleManagerRef` API (needs access to commonParams, not exposed → hard). Needs in-game verification. |
| I16 | Auto-rename on creation (apply preferred scheme when a line gets ≥2 stops) and extra schemes (e.g. "Carrier Nr – First–Last", "Cargo: A → B"). | 3 clicks per batch → 0 | New schemes: data resources (easy). Auto-apply: needs hook in line creation (local `reactLineCommit` callback) → fork (hard) or a game script watching new lines (medium, needs verification). |
| I17 | Overlength warning surfaced in stop row / store when consist longer than platform. | Hidden → visible | Stop row via `LineCargoDisplay` (exported, rendered in each stop row line_manager_panel.tl:915) → replace/wrap to add a warning icon using `checkLineStopForVehicleOverlength` → medium-easy. |
| I18 | Fix vehicle-list sort bug (line grouping) and make vehicle list sortable. | Correct grouping | Part of I4 (replace exported `VehicleList`) → medium. |

Unknowns needing in-game verification: whether `onActivate` in the store list is double-click or Enter; whether Question feedback items auto-expire after 5 s; whether `sendVehiclesToDepot` from SEND_TO_LINE mode really ignores the clicked depot; whether file-level overrides of `.tl` GUI files are possible for mods (affects "hard" ratings).
