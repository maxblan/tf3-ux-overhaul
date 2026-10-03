# Flow audit v2: missed and under-served player flows

Date: 2026-10-03. Source: the extracted game build in `.game/game/` (the same build as `docs/inventory/`). Paths are relative to `.game/game/gui/gui/` unless they start with `game_mechanics/`, `scripts/`, `apidef/` or `src/`.

This audit followed the v2 direction:
- Improve the vanilla screens in place, as if they had always worked this way.
- Add new UI only when nothing else works, and then in vanilla style.
- Add nothing new for the player to learn.
- No new notifications, and no change to which notifications are hidden.

Items that were already done or rejected at the time of the audit (see the brief in `PLAN.md` and the commit `041576a`) are not proposed again. Several proposals have been built since; the Status column in section 1 shows which.

Method: a full play session was split into seven areas:
- vehicle store
- line editing
- construction
- money and company
- entity windows
- shell, save and load
- layers and statistics

Every claim was traced to code. The top items were checked a second time by hand: ProblemsCell equality, quit/load/save paths, `groupSaves`, the sublistId tab bug, `newLine` with selected vehicles, the `customFilters` side effect, Sell, the accordion, the store sort default, the mission counter in the store table, and the export status of every hook named below.

Ratings: effort is E (easy: wrapper, patch or data, under about 100 lines), M (medium: small fork or a hack that needs verification) or H (hard: big fork). Value is high, med or low.

## 0. Enabling hooks found during the audit (shared by many items)

These make most proposals cheap. Each one is called through a module table at runtime or is an exported recipe.

| Hook | Where | Kind | Reaches |
|---|---|---|---|
| `entity_window_util.ActionButtonBar` | entity_window_util.tl:1187 | exported recipe. Wrap it and edit `primaryButtons`/`secondaryButtons` by `tag`. `customItem` (:1119) lets one button be swapped for our own stateful recipe. | Sell/discard confirmations and button labels in all 6 action bars |
| `content_card.makeContentCardsCollapsibleFunctions` | main/content_card.tl:457 | module function, called through the table by 15 call sites | Collapsible sections in every entity window |
| `content_card.ContentCard` | main/content_card.tl:207 | exported recipe. It can detect local content recipes by `react.GetRecipeName` (react.lua:441). | Local cards such as `TownLevelWidget`, `SuppliersWidget`, `VehicleBalanceGraph`. One central recipe, so keep the wrapper thin. |
| LVM `commonParams` capture | `line_util.makeLineActionDescriptor` (called at manager_window.tl:435, 817, 992, 1157, 1308), or the exported `vehicle_list_react_util.VehicleList` (`params.commonParams`) | patch or wrap | `newLine`, `moveStop`, `openCargoFilter`, `addFeedback`, and `vehicleStoreOpenForDepotAndLineRef` (which line a purchase is for). These functions are reassigned on every render, so wrap them through a metatable proxy (`__newindex`). Chain with zhenya_auto_assign_terminals, which also patches `makeLineActionDescriptor`. |
| `line_util.autoLoadConfig` | line_util.tl:494, called at manager_window.tl:6712, 6786, 6845, 6879, 6963 | module function | Automatic cargo config |
| `vehicle_react_util.HandleVehicleChanges` | vehicle_react_util.tl:319, called at vehicle_store_window.tl:4655 and manager_window.tl:8549 | module function | Every buy, replace and modify |
| `vehicle_store_window.VehicleStoreWindow` | vehicle_store_window.tl:4580 | exported; every opening goes through it (:4893/4930/4967) | Store title and transport modes |
| `construction_react_util.getActionParams` / `forEachDefinition` / `getMenuCategories` | construction_react_util.tl:3604 / 2774 / 3999, called at construction.tl:4437 / 4284 / 4363 | module functions | Proposal tooltip (`getProposalStringsFn`), every definition's params, menu grouping |
| `company_util.getConstructionDisableReason` | game_mechanics/company/company_util.tl:171, called at construction_react_util.tl:1176, 1184 | module function | The "why is this locked" text in the construction callout. Patch it in the GUI state only; the sim script calls it too. |
| `savegame_react_util.groupSaves`, `.SavegameCard`, `.SavegameSelectCard` | menu/savegame_react_util.tl:121, 244, 848 | function and exported recipes | In-game Load page |
| `subvention_util.makeDefaultCardData` | game_mechanics/subventions/subvention_util.tl | module function, used by all four subsidy scripts | Subsidy card text |

Hooks that are possible but hacky (flag them, and use them only behind a self-check):
- Wrapping `lang_util.format` for one template string (the game-bar Company tooltip).
- A value-matched `react.useState` patch (the store sort default).
- Patching `app.quit`/`app.stopGame`. Whether the engine `app` table is writable needs in-game verification.

## 1. Ranked overview

Ranked by value divided by effort. The fixes to our own code come first. The Status column is as of 2026-10-03. "Out of scope" items touch save, load or quit, and v2 changes gameplay screens only (see `PLAN.md`). #17 still lacks the age-% column and the hand-off to the Line Manager.

| # | Flow | Proposal (what the player notices) | Effort | Value | Status |
|---|---|---|---|---|---|
| 1 | Statistics → Problems (all tabs) | The Problems icon updates live (it no longer sticks after a fix), and the tooltip lists the problems | E | high | open |
| 2 | Statistics → Lines (our feature) | Our bug: the "Problems" quick filter always shows nothing; it also re-filters every frame | E | high | done |
| 3 | Sell from the vehicle window | Sell asks first, with the same question tape as the Line Manager | E | high | done |
| 4 | Any entity window | Opened sections stay open next time, and several can be open at once | E | high | done |
| 5 | Load the latest progress (in game) | The Load card loads the newest save, autosave included | E | high | out of scope (save/load) |
| 6 | Load another save (in game) | "All unsaved progress will be lost." asks before loading | E–M | high | out of scope (save/load) |
| 7 | Perk locked after a promotion | The lock reason says "Promotion pending – open the Company window" instead of contradicting the bar | E | high | done |
| 8 | Vehicle store | Newest model listed first and preselected; the sort choice is kept | E (hacky) / M | high | done (list layout only) |
| 9 | Town not growing | The level card says "Growing slowly – limited by Traffic" and shows "43 % to Small Town" as text | E–M | high | done |
| 10 | Bulldozing a station | The bulldozer tooltip warns "Removes *Name* – 3 lines stop here" | E–M | high | done |
| 11 | Road network + bus stops | Road and Roads show all road tabs (mirror merge, like Rail+Tracks) | E–M | high | done |
| 12 | Extending a hand-configured line | New stops still get automatic cargo | E–M | high | open |
| 13 | Configure opens the module tab (done feature) | Vanilla bug sends the sublistId to the wrong tab in the dynamic Modules menu; a workaround is needed | M | high | worked around (module tab order) |
| 14 | Quit | Quit asks first and offers Save & Quit | M | high | out of scope (save/load) |
| 15 | Station click with several lines selected | No longer moves every selected vehicle onto a new one-stop line | M | high | done |
| 16 | Replace a fleet | "Replace 12 vehicles for $X?" before an instant mass replace | M | high | done |
| 17 | Find old or losing vehicles | Vehicles tab: quick filters, totals, age as % of lifespan, hand-off to the LVM | M | high | partly done (filters, totals, red age, age sort) |
| 18 | Find crowded or idle stations | Stations tab: quick filters (incl. "No lines"), totals, correct Utilization sort | M | high | done |
| 19 | Choose or repay a loan | Correct interest label and total cost; "Repay $X" with the interest saved | M (fork ~400) | high | open |
| 20 | Save over the current game | No overwrite dialog when the name is the current game (it matches F10) | E (hack) / M | med-high | out of scope (save/load) |
| 21 | Why is my line stuck? | Full-load stops show the vanilla load-mode icon in the stop row | E | med-high | open |
| 22 | Station/landmark menu when money is short | The callout price turns red when unaffordable (vanilla already does this for custom actions) | M | med-high | open |
| 23 | Buy a train for a line | Store title shows the line and the shortest platform | E–M | med-high | open |
| 24 | Read the vehicle action bar | Secondary icons get their existing labels as captions | M | med-high | open |
| 25 | Electric locos on non-electrified lines | Not offered for that line (like large aircraft for small airports) | M | med-high | open |
| 26 | Town rating tiles and layer HUD | "Traffic · Poor" as text next to the colour | E | med | open |
| 27 | Bridge/tunnel choice | Tooltip names the current type and its speed limit | E | med | open |
| 28 | Subsidy offer | "Offer ends in 1 month" and "Due {date}" | E | med | open |
| 29 | Perk "Already built" | "…another one at rank Director" | E | med | open |
| 30 | Vehicle profit | "Last 12 months: +$X" in the Balance card | E | med | open |
| 31 | Warehouse "Discard All Cargo" | Asks first | E | med | open |
| 32 | Configure Stop | Always opens fresh for the clicked stop (stale state) | E | med | open |
| 33 | Vehicle hover tooltip | Shows the line ("Line 4" / "In Depot") | E | med | open |
| 34 | Finance window | Reopens on the tab used last | E–M | med | open |
| 35 | Statistics after loading | Our replaced tabs keep sort and quick filter across save/load | E–M | med | open |
| 36 | Cargo Satisfaction layer | Keeps the chosen cargo | E | med | open |
| 37 | Notification log (reading) | Date always visible (CSS); search in a later step | E? / H | med | open |
| 38 | Celebrations | Click acts and dismisses; no crash on an empty queue; paused while the game is paused | E (copy 233) | med | open |
| 39 | Moving a stop | Automatic cargo is recalculated, as for every other edit | M | med | open |
| 40 | Adding a stop | Tooltip names the position and warns about the wrong carrier | E–M | med | open |
| 41 | Rank tax and rank progress | "Ticket income at this rank: 96 %"; one consistent progress figure with population numbers | M (hacky) | med–high | open |
| 42 | Industry suppliers | Tables sorted by Received; per-cargo counts fixed | M | med | open |
| 43 | Industries tab | "0 %" workload shown for starving processors | M | med | open |
| 44 | Account tooltip | Debt and monthly loan payment | E (if writable) | med | open |
| 45 | ConstructionWindow tabs | Each station tab gets its own type label (bug) | M | med | open |
| 46 | Store comparison | Running cost and lifespan columns in Table layout (fixes a mission bug too) | M | med | open |
| 47 | Calendar speed | Shown next to the date only when it is not 1x | E | low-med | open |
| 48 | Tram/bus-lane tools | Options in the bottom bar instead of a second window | E | low-med | open |
| 49 | Achievements tab | Vanilla "cannot be earned" tape plus "x / y" | E | low-med | open |
| 50 | Junk one-stop lines | Discarded when deselected (debatable) | M | med | open |
| 51 | Line search | Also finds lines by stop/station name | H (8.5k fork) | high | open |
| 52 | Cargo waiting at cargo terminals | Station window counter shows cargo | H (1,069 fork) | med-high | open |

The full entries follow, in the same order. Section 4 lists the vanilla bugs, section 5 what was considered and rejected, and section 6 the in-game checks.

## 2. Proposals in detail

### 1. Statistics Problems column updates live
- Flow: fix a broken line, stuck vehicle or crowded station while Statistics is open, then check the warning is gone. Or sort by Problems.
- Vanilla friction:
  - `ProblemsCell` passes `warnIdsLess` as the *equality* function: `useStepStateTimer(makeState, nil, warnIdsLess)` (statistics/statistics_react_util.tl:353).
  - The timer skips the update when `stateEqualsFn(new, old)` is true (main/engine_react_util.tl:150). `warnIdsLess(new, old)` is true whenever the new list is shorter: with an empty `new` the loop is skipped and it returns `0 < #old`.
  - So a fixed problem never disappears from the cell.
  - The cell also reads `userParam.notificationState`, which was captured at cell creation (`userParam` is not updated for existing cells, scripts/builtin.d.tl:1170). New problems on existing rows are not shown either.
  - The sort uses fresh data, so icons and order disagree.
  - With more than one problem the tooltip says only "There Are Several Problems" (:327).
- Change: the icon appears and disappears live, and the tooltip lists each problem title.
- No load: same icon, now correct.
- Route: replace the exported `statistics_react_util.ProblemsCell` (:346) with a copy of about 60 lines that includes the local `WarningIcon` (:317-344).
  - Read the notification state through a cache refreshed at most once per frame.
  - Use default deepEquals.
  - This fixes all 6 vanilla tabs plus ours.
- Rating: E / high.

### 2. Our Lines "Problems" quick filter (our own bug) and per-frame cost
- Status: done.
- Bug: `hasProblems` checks `type(value) == "number"` (src/ui_overhaul/content/ui_overhaul/gui/statistics_lines.lua:182-185). `getProblemsCompareValue` returns `{count, ids}` (statistics_react_util.tl:305-311), so the filter is always empty.
  - Fix: `return value[1] > 0`.
  - Add a spec.
- Performance: `tableState` uses `useStepState` (statistics_lines.lua:283), so on every frame it runs `makeFilteredKeys`, which calls `calculateBalance` per line for the "losing" filter. Switch to `useStepStateTimer(…, 1.0)`.
- Rating: E / high.

### 3. Sell from the vehicle window asks first
- Status: done.
- Flow: sell a vehicle from its window.
- Vanilla friction:
  - The Sell icon sends `makeVehicleSellCmd` at once and plays the sell sound on the first click (entity_window/vehicle/vehicle.tl:523-535, 358-367).
  - The Line Manager asks for the same action ("Sell Selected Vehicle", Accept/Cancel, manager_window.tl:5334-5350).
- Change: the first click turns the slot into the vanilla question "Sell Selected Vehicle? [Sell] [Cancel]".
- No load: the same wording and tape as the Line Manager; it is already translated.
- Route: wrap the `ActionButtonBar` recipe.
  - For the entry with tag `entityWindow.vehicle.sell`, set `customItem = UioConfirmButton{orig = entry}`: a small recipe that holds the armed state and calls the original `onClick` on accept, which keeps the protected-entity feedback.
  - Drop `sound` from the first click.
  - No fork.
- Rating: E / high.

### 4. Entity-window sections remember their state
- Status: done.
- Flow: reopening an industry or town and expanding Suppliers, Passengers or Stocks again every time.
- Vanilla friction:
  - Every window calls `makeContentCardsCollapsibleFunctions(state, true)` (vehicle.tl:231, industry.tl:283, town.tl:1203, warehouse.tl:45, station_group.tl:848 and others).
  - `onlyOneExpandable = true` collapses the other sections (main/content_card.tl:463-467).
  - The state is per-window `useState`, so everything is collapsed again on reopen.
- Change: a section you opened stays open next time for that kind of window, and opening one no longer closes the others.
- No load: nothing new to see; the window stops forgetting.
- Route: monkey-patch `content_card.makeContentCardsCollapsibleFunctions` (module function :457) with a module-level `remembered[key]`.
  - `isExpanded` falls back to `remembered`; updates write both.
  - Ignore `onlyOneExpandable`.
  - Keep key `""` (collapse all, don't remember), which vehicle.tl:497 uses before Modify.
- Caveats:
  - With Input and Output both open, the industry flow arrows show only the inputs (`if/elseif`, industry.tl:330-357).
  - An expanded card registers its own `IA_MENU_BACK` (content_card.tl:356-360). Check the Esc order in game.
- Rating: E / high.

### 5. The in-game Load card loads the newest save
- Status: out of scope (save/load).
- Flow: "load where I was".
- Vanilla friction:
  - `groupSaves` takes the first manual save as `mostRecent` (menu/savegame_react_util.tl:159-163).
  - The card date, the Date sort, the Load button (:345) and the preselected details row (load_game_page.tl:144) all use it.
  - A newer autosave or exit save is only visible in the details. Main-menu "Continue" uses `getLastGame()` (main_page.tl:324), so the two paths behave differently, and hours of autosaved progress can be skipped silently.
- Change: the card shows and loads the newest save of the group, whether manual, autosave or exit, but never a recovery save. The details are unchanged.
- No load: same card. It just does what it seems to promise.
- Route: monkey-patch `savegame_react_util.groupSaves` (:121; called through the table at load_game_page.tl:34, 37 and savegame_react_util.tl:853, 862).
  - Post-process `mostRecent`/`mostRecentIndex`.
  - Re-sort in Date mode.
  - The Save page filters to Manual and is unaffected.
  - The main-menu Load page stays vanilla, because there is no replacement pass outside the game GUI.
- Rating: E / high.

### 6. Unsaved-progress warning before an in-game load
- Status: out of scope (save/load).
- Vanilla friction: all three in-game load paths call `app.loadGame` immediately:
  - card button: savegame_react_util.tl:341-345
  - details double-click: :1105-1108
  - details button: :1150-1153
  - Consoles already have the "All unsaved progress will be lost." dialog (main/pause_menu.tl:15-45).
- Change: the same vanilla dialog (Load Game / Cancel) before an in-game load.
- No load: vanilla dialog, shown only on a destructive action.
- Route: wrap the exported `SavegameCard` (:244) and `SavegameSelectCard` (:848). Hand them a proxied `commonParams` with `inGame = false` and a `setPage` that intercepts `"ProgressPage"`.
  - Every non-inGame branch defers loading into `onMount` (:347-355, 1110-1121, 1155-1164). The proxy shows the dialog and calls `onMount` on accept.
  - Restore `inGame` for `ModSelectorPage` (mod_selector_page.tl:1515; wrap its module return :682).
  - About 70 lines, and all strings exist.
- Rating: E–M / high.

### 7. Promotion pending: say so where the player hits the lock
- Status: done.
- Flow: "I was promoted; why can't I build the new perk?"
- Vanilla friction:
  - The script raises `potentialLevel` (game_mechanics/company/company_growth.script.tl:47).
  - The applied `level` changes only through `applyLevel`, which is sent only when the Company window's rank view mounts (company/company.tl:420-422).
  - Unlocks read `level` (construction.tl:209-212, company_util.tl:92), while the game bar shows `potentialLevel` (game_bar/game_bar.tl:403).
  - So the bar says "Manager" while the perk says "Unlocked at Rank: Manager" (company_util.tl:176).
  - The rank-up notification auto-dismisses (company_growth.script.tl:103).
- Change: a rank-locked perk whose rank is already reached says "Promotion pending – open the Company window to unlock".
  - Auto-applying was considered and rejected, because it would skip the vanilla unlock ceremony.
- No load: only existing reason text, and it removes a contradiction.
- Route: monkey-patch `company_util.getConstructionDisableReason` (GUI state only; called through the table at construction_react_util.tl:1176, 1184). Compare `minRank` against `company_progression_util.getCompanyProgressionState(player).potentialLevel`.
  - Optional, hacky: the Company button tooltip ("Promotion ready…") via a `lang_util.format` template hook at game_bar.tl:466. `CompanyButton` is local (:378).
- Rating: E / high.

### 8. Vehicle store: newest model first, and the sort is remembered (D6, refined)
- Status: done for the list layout only.
- Vanilla friction:
  - The sort starts as `{mode="YearFrom", ascending=true, groupTypes=true}` (line_vehicle_mgmt/vehicle_store_window.tl:2550-2554), and the selection index starts at 1 (:2541-2544).
  - The list gets focus on mount (:2974-2979), so the details pane, the Buy button, Enter and the cart all target the oldest model.
  - Tab, filters, search and sort all reset on every opening (comment at :4472). Only the layout style persists (:4865).
  - Table layout is the same: column 2, `yearFrom` ascending (vehicle_store_table.tl:366-371, 540-541).
- Change: newest first, newest preselected, and the last sort choice kept for the session.
- No load: same controls, better default.
- Route (smallest first):
  - (a) In `doReplaceFn`, patch `react.useState` to substitute `ascending = false`, or a remembered sort through a small `old`/`set`/`transform` proxy. Only when the initial value is a table with exactly these three fields; that pattern occurs only at :2550 (grep). If the pattern stops matching it falls back to vanilla silently. About 15 lines, but hacky: flag it and self-check.
  - (b) Table layout: fork the exported `VehicleStoreTable` (587 lines) and combine with #46 and bug B-V1.
  - (c) Clean fallback: fork about 4,680 lines. Everything under `VehicleStoreWindow` is local, so the backlog's "~2.5k" is too low.
- Rating: E (hacky) / M / high.

### 9. Town window: name the growth bottleneck
- Status: done.
- Vanilla friction:
  - Authority is the minimum of the six ratings (`calcAuthorityScore`, game_mechanics/towns/town_util.tl:745-771).
  - Growth is the authority level × the supplies factor, and 0 without supplies (:606-632).
  - The bottleneck is therefore exactly "the worst rating, or supplies", but the level card only says "Growing Slowly", and progress % is tooltip-only (entity_window/town/town_eow.script.tl:85-95).
- Change: inside the existing level card, "Growing Slowly – limited by Traffic" (or "– no supplies"), plus "43 % towards Small Town" under the bar.
- No load: one line in a card already shown; it replaces an up-to-8-tab hunt.
- Route: `TownLevelWidget` is local (:26). Either fork the exported `TownLevelPlugin` (:124, about 110 lines), or use a thin ContentCard wrapper on "TownLevelWidget". Data: the same parallel rating functions the dashboard calls (`GetRatingsDashboard`, game_mechanics/towns/town_react_util.tl:2149-2205).
- Rating: E–M / high.

### 10. Bulldozer: warn before removing a station that is in use
- Status: done.
- Vanilla friction:
  - No undo.
  - A confirmation dialog is impossible: `ConstructionActionParam` has no veto callback (scripts/builtin.d.tl:1356-1380), and `onProposalApply` fires afterwards.
  - The only pre-click text is the reputation line (construction_react_util.tl:3812-3864). It says nothing about stations or lines.
- Change: when hovering a station with the bulldozer, the tooltip adds "Removes station *Name* – 3 lines stop here". It appears only when true.
- No load: the existing tooltip, only in the dangerous case. It stands in for the confirmation that cannot be built.
- Route: patch `getActionParams` (:3604) and wrap `constructionActionParams.getProposalStringsFn` when `bulldozer ~= nil`.
  - Walk `proposal.toRemove_native` (pattern: game_mechanics/towns/town_util.tl:1049ff).
  - For CONSTRUCTION entities, take `stations`, then `lineSystem.getLineStopsForStation`.
  - Needs in-game check that `toRemove` holds the construction.
- Rating: E–M / high.

### 11. Road + Roads mirror merge
- Status: done.
- Vanilla friction:
  - Bus and truck setup needs ROAD (stops, depots) and ROADS (road types, lanes, traffic lights, `roads_tools`).
  - Each has a "Tools" tab with the same icon, and their contents differ (bus/tram tools only in `roads_tools`; tools/bus_lane_tool.script.tl:35-40).
  - This is the same back-and-forth that Rail+Tracks had.
- Change: both buttons open a menu that holds all road tabs. Road opens at Buildings and Roads at the road types. There is one Tools tab.
- No load: the same buttons, hotkeys and tabs; they are just no longer split.
- Route: patch `getMenuCategories` (:3999). Give each menu its own entries first plus the other menu's entries, and merge `road_tools` into `roads_tools`.
  - Mirror, don't move: an empty menu disables its game-bar button through `constructionMenuCategoryEmpty` (game_bar.tl:608-613, 631), and the button is local.
  - Check that the Rail+Tracks implementation avoids this trap too.
  - Every menu key must stay a table: `ipairs(menuCategories[menu])` at construction.tl:4012.
  - Known regression: tabs shown in the "foreign" menu lose their context-help page, because pages are keyed by element id (context_helper/context_helper_react.tl:28-160). The same applies to Rail+Tracks.
- Rating: E–M / high.

### 12. Stops added to a hand-configured line still get automatic cargo
- Vanilla friction:
  - Any Configure Stop commit, even a wait-time change, sets `customFilters = true` (line_vehicle_mgmt/cargofilter_window.tl:438).
  - `autoLoadConfig` then returns early for the whole line (line_util.tl:494-497).
  - New stops start with every load flag false (line_util.tl:471); passengers are only added inside `autoLoadConfig`.
  - Every stop added later therefore loads nothing, and nothing says why.
- Change: new stops on a manually configured line get the automatic suggestion for that stop only. Hand-configured stops are untouched.
- No load: it works as expected.
- Route: wrap `line_util.autoLoadConfig`. When `customFilters` is set, run the original on a copy with it cleared, then copy back only the new stops.
  - New stops can be recognised: `makeNewStop` sets no `minWaitingTime`, while stops read from the game always have one (line_util.tl:99-104 vs 486-489).
  - No fork; this does not touch `LineManagerPanel`, so there is no conflict with celmi.
- Rating: E–M / high. Check in game that passengers do not board when the flag is false.

### 13. "Configure opens the relevant module tab" is affected by a vanilla bug
- Status: worked around by ordering the module tabs (route a).
- Evidence:
  - The `constructionMenuSetTab{sublistId}` handler passes the data index of the sublist to `setActiveTab` (construction.tl:2809-2821).
  - `setActiveTab` expects a position in `shownSublistsState` (:2796-2806).
  - In the dynamic MODULES menu, empty sublists are left out (`if found or not params.dynamic`, :2634).
  - So whenever an earlier module tab (Plots or Warehouse at order 0) is empty for a station, the wrong tab opens, or the index goes out of range and errors.
- Change: our Configure → Tracks/Platforms lands on the right tab every time.
- Route: the bug is in local `ConstructionCategory`, so fixing it needs a fork. Workarounds:
  - (a) In the patched `getMenuCategories`, order the module categories so that the target tabs come before anything that can be empty.
  - (b) Compute the shown position ourselves and fire `tabIndex` plus the shifted index. Verify per station type in game.
- Rating: M / high (correctness of a shipped decision).

### 14. Quit asks first and offers Save & Quit
- Status: out of scope (save/load).
- Vanilla friction:
  - On PC, "Return to Main Menu" calls `app.stopGame()` and "Return to Desktop" calls `app.quit(true)` immediately (main/pause_menu.tl:191-193, 205-207).
  - The console branch already uses `quitWithConfirmation` with "All unsaved progress will be lost." (:15-45).
  - Save, then quit costs 7 actions, because saving closes the pause menu (save_game_page.tl:206).
  - The rack buttons are not disabled during an autosave (B-S3).
- Change: both buttons show the vanilla dialog with Cancel, Quit and Save & Quit (saves under `getDefaultSavegameId()`, then quits in the callback).
- No load: the console dialog; Save & Quit removes 4 actions from the most common ending.
- Route: `PauseMainPage` is local.
  - (A) Wrap the `PauseMenuTool.push`/`.pop` fields to track "menu open", and patch `app.stopGame`/`app.quit` to show `dialog_react_util.DialogWindow` (exported, dialog_react_util.tl:124). About 50 lines. Whether `app` is writable needs in-game verification.
  - (B) Fallback: fork pause_menu.tl (437 lines, flag it).
  - One new string, "Save & Quit".
- Rating: M / high.

### 15. Clicking a station with several lines selected must not move their vehicles
- Status: done.
- Vanilla friction:
  - Ticking 2 or more lines, or the master box, selects all their vehicles and switches the LVM to MAIN mode (manager_window.tl:1699-1745, 6438-6450).
  - In MAIN mode a station click calls `commonParams.newLine(sgDetails, selectedVehicles)` (:311). That stores the vehicles (:6708-6710) and sends all of them to the new one-stop line (:6479-6501).
  - The tooltip says only "Create new line starting at {name}." The honest "…and assign {count} vehicles." string exists but is used only in Send-to-Line mode.
  - Esc does not clear a vehicle-only selection (:7451-7472).
  - This is more likely now that our map clicks keep the LVM open.
- Change: with 2 or more lines selected, the station click creates the line without moving vehicles. Deliberate vehicle selections keep vanilla behaviour, but the tooltip uses the existing "assign {count} vehicles" string.
- No load: an accidental mass move stops happening.
- Route: capture `commonParams` (section 0) and wrap `newLine`: if `#lineManagerStateRef:get().lineListEntitiesSelected >= 2`, call the original with `{}`. Wrap the exported `manager_tooltips_util.CreateLine` for the text.
- Rating: M / high.

### 16. Confirm before replacing many vehicles
- Status: done.
- Vanilla friction:
  - Selecting a line selects its whole fleet. In Replace mode, double-click or Enter (vehicle_store_window.tl:1527-1562), or a single click on a Table-layout price button (vehicle_store_table.tl:323-333), replaces every selected vehicle at once.
  - The list has focus and the oldest model preselected (#8), so Enter right after opening replaces N vehicles with the oldest model.
  - `makeVehicleReplaceCmd` swaps in place, mid-route, with no callback (vehicle_react_util.tl:405).
- Change: when more than one vehicle would be replaced or modified, the Line Manager asks "Replace 12 vehicles for $X?". Single replaces stay instant.
- No load: the vanilla question tape, as in our clone confirmation.
- Route: patch `vehicle_react_util.HandleVehicleChanges`. When `#changes > 1` and the changes target existing vehicles, defer into `commonParams.addFeedback(msg, "Question", {onAccept=…})`.
  - Cost = price × N − Σ `getDepreciatedValue` (the maths at vehicle_store_window.tl:3577-3591).
  - Without a captured `commonParams` (entity-window path, always 1 vehicle), pass through.
  - Also pass `onFail`, which fixes the silent failures (B-V7).
- Rating: M / high.

### 17. Statistics → Vehicles: the same quick filters and totals as Lines
- Status: partly done. The quick filters, the totals row, the red Age cell and the age sort are built; the age-% column and the hand-off to the Line Manager are not.
- Vanilla friction:
  - Age sorts by `purchaseTime`, so "ascending age" puts the oldest first (statistics/statistic_vehicles.tl:312-314).
  - The share of lifespan is computed but never shown (`agePercent`, line_vehicle_mgmt/vehicle_util.tl:297-313, no reader).
  - No totals.
  - Acting means one window per vehicle.
- Change:
  - Quick filters "All / Losing money / Problems / Old (lifetime reached)".
  - A totals row with count, capacity, utilization and 12-month balance.
  - The Age cell turns red past the lifespan, with the existing tooltip "{total} of Lifetime ({age} Remaining)" (line_eow.script.tl:142-146).
  - The count in the totals row opens the LVM with exactly these vehicles selected (`openVehicleManager{openWithVehicleEntities}`). The existing bulk Replace/Sell/Depot buttons then apply.
- No load: the same pattern and wording as our Lines tab.
- Route: the module return `VehiclesStatistic` (:475), ported like `statistics_lines.lua` with a pcall fallback (about 475 lines).
  - Balance: `calculateBalance({v}, now-1y, now, true)`.
  - Filtering: use `useStepStateTimer(…, 1.0)`.
  - Share `QuickFilterBar`/`Totals` with Lines.
- Rating: M / high.

### 18. Statistics → Stations: quick filters including "No lines", totals, correct sort
- Status: done.
- Vanilla friction:
  - Utilization shows `used/(capacity+waitingHall)` but sorts by `{used, capacity}` (statistic_stations.tl:135-141 vs 242-245).
  - The engine's `overflow` flag is unused.
  - Stations without lines are dropped (:265). The known F-S5: idle upkeep cannot be found.
- Change:
  - Quick filters "All / Problems / Crowded / Unhappy / No lines". "All" stays vanilla.
  - A totals row (waiting/capacity, unhappy, upkeep). Under "No lines", the upkeep total is money wasted.
- No load: hidden stations appear only when asked for.
- Route: port the module return `StationsStatistic` (:387, about 390 lines), with the same pattern as #17. Fix bug B-T2.
- Rating: M / high.

### 19. Loan cards: honest interest, total cost, safe repay
- Vanilla friction:
  - Interest is a flat share of the amount over the whole term: monthly `pct × amount/months` (game_mechanics/finance/loan_util.tl:101-111), so the total is `pct × amount`. The card labels it "Annual Interest Rate" (finances_loan_gui.tl:346-350). A "12 %" 24-year loan costs 0.5 %/year; a "3 %" 1-year loan costs 3 %/year.
  - Repaying early waives the remaining interest (the interest part is commented out, loan.script.tl:171-190), but nothing says so.
  - Repay is greyed silently when cash is short (finances_loan_gui.tl:283-288).
  - One click repays tens of millions, and the offer cannot be re-borrowed.
- Change:
  - "12 % of amount · $7.2M interest in total".
  - The obtained card's button reads "Repay $X"; that is the confirmation, without a dialog. Tooltip: "Saves $Y interest" or "Needs $X".
  - With the same fork: "New offer around {date}", "Offer valid until {date}", and "Maximum of 4 loans".
- No load: existing labels corrected; no new elements.
- Route: `DefaultLoanCard` is local. Replace the exported `LoanBoard` (:483) with a copy of the card and board code (about 400 of 655 lines; flag it). Data: `loan_util.getFullLoanAndInterestPayBack` (:169).
- Rating: M / high.

### 20. Save over the current game without the overwrite dialog
- Status: out of scope (save/load).
- Vanilla friction:
  - The name is prefilled with the current save (save_game_page.tl:157-158), so the overwrite dialog always appears (:74-84).
  - Cancel is the primary button (:39-53), and `DialogWindowContent` focuses the first primary button. Type, Enter, Enter therefore cancels silently.
  - F10 overwrites the same name without asking.
- Change: no dialog when the name equals `getDefaultSavegameId()`. Overwriting *another* game's save still asks.
- Route:
  - (a) Wrap the exported `SaveGamePage` (:154) with a proxied `windowContainer` that auto-accepts this one dialog (about 30 lines; hacky).
  - (b) Fork `SaveGamePage` (330 lines), which also fixes B-S1.
- Rating: E/M / med-high.

### 21. Full-load stops visible in the stop list
- Vanilla friction: the stop row shows only cargo icons (`LineCargoDisplay{stopCargoDisplay=true}`, line_manager_panel.tl:915). Loading mode and stop times are hover → Configure Stop, one stop at a time. "Why is my line stuck?" is usually a forgotten Full Load.
- Change: stops that are not "Load if Available" show the vanilla `load-mode_full-any/all.tga` icon, with the vanilla tooltip "Full Load (Any/All)".
- No load: known icons, shown only on unusual stops.
- Route: wrap the exported `line_react_util.LineCargoDisplay`: `CallOriginalRecipe` plus an icon when `stopCargoDisplay`. Read `stops[i].loadMode` in a timer. Outside `LineManagerPanel`, so no celmi conflict (assuming celmi's stop row still calls it).
- Rating: E / med-high.

### 22. Construction callout price red when unaffordable
- Vanilla friction: the callout cost is never coloured (construction_desc_react_util.tl:368-401), but custom actions colour it red through `getPlayersBalance` (construction_react_util.tl:1208-1254). Inconsistent.
- Change: in the hover callout, the price uses the vanilla error colour when the minimum cost is more than the balance. Per-km items are skipped.
- Route: patch `construction_desc_react_util.formatNumbers` (:816, called through the table at construction.tl:3526) to flag the cost entry. Replace the exported `ConstructionInfoNumberList` (:906-973, 67 lines) to add class `error` to the flagged item.
- Rating: M / med-high.

### 23. Store title names the line and the shortest platform
- Vanilla friction:
  - The title is only "Buy Vehicles At {depot}" (manager_window.tl:7136-7140). The line is hidden in the buy callback.
  - Train length is shown per cart row (vehicle_store_window.tl:3783-3835) with nothing to compare it to. Overlength shows only later ("Terminal is too short", line_manager_panel.tl:435).
- Change: "Buy Vehicles for {line} At {depot}". Rail and tram add "· Shortest Platform: 160 m" when the line is known (also for Replace and Modify).
- No load: the same text slot.
- Route: wrap `VehicleStoreWindow` (:4580) and rewrite `params.title`.
  - The line comes from the captured `commonParams.vehicleStoreOpenForDepotAndLineRef` for Buy, or from `transportVehicle.line` for Replace/Modify.
  - The length is the minimum over stops of `line_util.getTerminalLength(station, terminal+1)` (exported, line_util.tl:1433).
- Rating: E–M / med-high.

### 24. Vehicle action bar: labels under the icons
- Vanilla friction: Reverse, Start/Stop, Clone (it buys a vehicle), Replace, Modify, Depot and Sell are icon-only. The label is a tooltip, and only for secondary buttons (entity_window_util.tl:1133, 1160).
- Change: the existing description appears as a small caption under each icon.
- No load: the same buttons, now self-explanatory.
- Route: the `ActionButtonBar` wrapper turns each secondary entry into a `customItem` copy of `makeActionButtonElement` (about 40 lines). Check the German width at 450 px in game.
- Rating: M / med-high.

### 25. Do not offer electric locos for non-electrified lines
- Vanilla friction:
  - Replace and Modify allow `{TRAIN, ELECTRIC_TRAIN}` on every rail line (line_util.tl:1710-1714).
  - The only check covers large planes and ships (:1591-1627). `isLineCompatibleWithTransportMode` exists (:1448-1484) but is never used for rail or tram.
  - The player finds out after paying ("Missing electric tracks.", manager_window.tl:5410).
- Change: for a line whose stops are not electrified, electric-only units are not offered, as vanilla already does for large aircraft.
  - Trade-off: electrify first, then buy.
- Route:
  - Wrap `line_util.getLineAndVehicleCompatibleTransportModesAndCarrier` (called through the table at manager_window.tl:5191, vehicle.tl:450/486).
  - Patch `vehicle_store_util.vehicleFilter` for electric-only `engineTypes`.
  - Needs in-game check of how TF3 models declare transport modes.
- Rating: M / med-high.

### 26. Town ratings in words as well as colours
- Vanilla friction:
  - Dashboard tiles show the level only as a CSS colour class (`TownRatingIconWithText`, game_mechanics/towns/town_react_util.tl:2225-2278).
  - Layer HUD rating bars set `hideText = true` (layers/layer_react_util.tl:129-137), and their tooltip is unreachable because the HUD is mouse-transparent.
  - The Towns tab tooltip is only the rating name (statistics/statistic_towns.tl:280-287).
- Change: "Traffic · Poor" on tiles, the vanilla label next to the HUD bar, and "Traffic: Poor" in the Towns tab tooltip. The labels come from `town_util.getRatingLabel`.
- No load: vanilla words; also helps colour-blind players.
- Route:
  - Wrap the exported `TownRatingIconWithText`.
  - Replace the exported `layer_react_util.TownRatingHudIcon` (:93-142, about 50 lines).
  - Wrap the exported `town_react_util.RatingBar` (:83).
- Rating: E / med.

### 27. Bridge/tunnel button names the current type
- Vanilla friction: the button is icon-only, with the static tooltip "Use this bridge type when needed." (construction_react_util.tl:2389).
  - A slow bridge chosen by hand silently stays when switching to fast track (`resetOnDefinitionChange=false`, :2397).
- Change: "Use this bridge type when needed – *Steel Truss* (160 km/h)".
- Route: wrap the exported `menu_category_util.FilterObjectsCalloutButton` (main/menu_category_util.tl:367-399) and extend `tooltip`.
- Rating: E / med.

### 28. Subsidy offer expiry
- Vanilla friction:
  - Offers expire after `expireDurationProposed` (game_mechanics/subventions/subvention_util.tl:277-290). That is never shown; the offer just becomes "Subsidy Missed".
  - The proposed card shows only the task duration, unlabelled (:356-370).
  - Active cards show the static duration while the bar shows the time remaining.
- Change: "Task time: 2 years · offer ends in 1 month" and "Due {month year}".
- Route: patch `subvention_util.makeDefaultCardData` to rewrite `deadline.name` only.
- Rating: E / med.

### 29. "Already built" tells when the next one comes
- Friction: "Already Built/Used" (company_util.tl:224-233), although further permits come at later ranks (`rankAndPermits`).
- Change: "Already built – another one at rank Director", or "– no further uses".
- Route: the same patch as #7, using `company_static_util.getExtraPermitsAggregatedPerRank()` (company_static_util.tl:73-90).
- Rating: E / med.

### 30. Vehicle 12-month profit as a number
- Friction: the Balance card is a 16-year chart only (vehicle_eow.script.tl:1194-1222).
- Change: "Last 12 months: +$X" at the top of the existing card.
- Route: fork the exported `VehicleBalancePlugin` (about 30 lines) and reuse our 12-month balance code.
- Rating: E / med.

### 31. Warehouse "Discard All Cargo" asks first
- Friction: the trash icon sends `makeStockListDiscardCargoCmd(…, 1.0)` at once (entity_window_util.tl:424-435).
- Change: the same armed confirm as #3.
- Route: wrap `entity_window_util.SendCommandButton` (:2438). This is its only caller.
  - Optional: tooltips on the unlabelled cargo pin buttons (:338-375). Needs a fork of about 220 lines.
- Rating: E / med.

### 32. Configure Stop always opens fresh
- Friction:
  - The cargo icons call `closeCargoFilter()` before opening (line_manager_panel.tl:923); the hover "Configure Stop" button does not (:941-951).
  - The singleton window then probably keeps the previous stop's uncontrolled checkbox and toggle state (cargofilter_window.tl:745-824). Needs verification.
- Change: every way of opening shows the clicked stop's real values.
- Route: capture `commonParams` and wrap `openCargoFilter` to close first.
- Rating: E / med.

### 33. Vehicle hover tooltip shows the line
- Friction: the tooltip is the name plus notification text (main/game_tooltips.tl:145-223). Finding which line a jammed bus belongs to costs a click, and layer clicks stack windows.
- Change: one line under the name: "Line 4" or "In Depot".
- Route: wrap the exported `DefaultEntityToolTip` (:145) and add `line_util.getVehicleInstructionName` (line_util.tl:1356-1366). Verify carriage→vehicle delegation.
- Rating: E / med.

### 34. Finance window reopens on the last tab
- Friction: `openFinanceWindow` defaults to "Overview" (main/game.tl:290-301), and every caller fires it without a tab (game_bar.tl:111, 322). That is +1 click on every visit to Finances or Loans.
- Change: it reopens on the tab used last this session.
- Route:
  - Record the tab by wrapping the exported `FinancesCharts` (game_mechanics/finance/finances_charts.tl:409), which receives `tabValue` on every tab change.
  - Inject it in our existing `ToolStack` replacement when the Finances tool is pushed with a nil tab.
- Rating: E–M / med.

### 35. Statistics sort and quick filter survive save/load (our replaced tabs)
- Friction: sort is kept per session only (statistics.tl:264, 673-688). Our quick filter is a Lua module variable (statistics_lines.lua:30).
- Change: after loading, the replaced tabs come back with the same sort column and filter.
- Route: `initialSortColumn = params.initialSortColumn or saved.sort`. Wrap `onSortColumnChange` and store in `api.gui.game.setGuiSaveData(modId, …)` (apidef/api/gui.d.tl:776-781).
  - Search and carrier toggles are owned by local `StatisticsContainer`, so they cannot be kept.
  - Expand/shrink would need a 706-line fork, which is not worth it.
- Rating: E–M / med.

### 36. Cargo Satisfaction layer keeps its cargo
- Friction: the filter is `useState({-1,1})` (layers/layer_cargo.tl:276-281) and resets on every open.
- Change: the combo shows last time's cargo.
- Route: replace the exported `layer_cargo.Layer` (:349) and fork only `CargoLayerWindowContent` (:265-347, about 85 lines).
  - Store the `cargoTypeId`, not the index, because the list is rebuilt from produced cargo.
  - Fire the saved config in `onMount`.
  - Infrastructure needs a whole-file fork (279 lines): medium value, later.
- Rating: E / med.

### 37. Notification log: date always visible (reading only)
- Friction: the date badge is visible only on hover (`visible`/`invisible` class toggle, game_mechanics/notifications/gui/notification_log.tl:176-188). There is no text search (:561-573).
- Change: the date is always shown as a dim annotation. No change to which notifications exist or are hidden.
- Route:
  - (a) A mod CSS override for that TextView (needs verification of mod CSS loading and overlap).
  - (b) A fork of the 654-line file plus swapping `NotificationLogTool` fields. Hard; search would come with it.
- Rating: E? / H / med.

### 38. Celebrations behave
- Friction:
  - After obsolete entries are dropped, `s.celebrations[1].type` is read without a check (game_mechanics/celebrations/celebration_react_util.tl:207-218). That is a Lua error when every queued entry was obsolete.
  - A left-click jumps the camera but leaves the callout for 10 s.
  - The timer uses application time (:191), so the queue cycles while paused.
- Change: no crash, a click dismisses, and the queue holds while paused.
- Route: replace the exported `CelebrationsContainer` (:133). In practice that is a copy of the 233-line file.
- Rating: E / med.
- Inventory correction: celebrations do have a Settings toggle (menu/settings_page.tl:525-528).

### 39. Moving a stop recalculates automatic cargo
- Friction: `addStop`, `removeStop` and `moveVia` call `autoLoadConfig` (manager_window.tl:6786, 6845, 6879); `moveStop` (:6851-6868) does not. A moved truck stop keeps loading the old station's cargo.
- Route: wrap `commonParams.moveStop` and send a follow-up `makeLineUpdateCmd` with auto config while `customFilters` is false.
- Rating: M / med.

### 40. Add-stop tooltip says where and whether
- Friction:
  - New stops are inserted after the current segment (manager_window.tl:6780-6789), and the tooltip says only "Add stop at {name}."
  - There is no carrier check: a rail station can be added to a bus line. The error appears later as a red segment with a hover-only "The stop is incompatible."
- Change: "…after stop 3", plus a warning line when the station does not serve the line's carrier.
- Route: wrap the exported `manager_tooltips_util.LMAddStop`. Use `getModeState()` and `line_util.getLineCarriers` vs `stationGroupSystem.getCarriers`. One new string.
- Rating: E–M / med.

### 41. Rank tax and rank progress made visible
- Friction:
  - Ticket income drops linearly to 50 % at Tycoon (`ticketPriceMultiplierAtMaxLevel = 0.5`, game_mechanics/company/company_growth_config.res.lua:6; company_progression_util.tl:25-40; applied in company_growth.script.tl:159-170). No UI mentions it.
  - The game bar % is relative within the level (game_bar.tl:398-406), while the Company window bar is absolute (company.tl:246-250). The two figures differ.
  - The progress driver (highest world population) is never named.
- Change:
  - In the Company rank header: "Ticket income at this rank: 96 %".
  - The bar tooltip: "30 % towards Director – world population 18,000 / 25,000".
- Route: `CompanyRankHeader` and `CompanyButton` are local. Use the `lang_util.format` template hook (hacky; flag it) or a 964-line fork of company.tl. Verify the multiplier semantics in game first.
- Rating: M / med–high.

### 42. Industry supplier and consumer tables
- Friction:
  - The tables list every matching industry, unsorted, in a 178 px box (industry_eow.script.tl:376-389; `initialSortColumn` unused).
  - Counts are keyed by entity, not by (entity, cargo) (:187, 192, 238, 259, 319, 338, 452, 471), so a two-cargo partner shows the same number twice.
- Change: sorted by Received/Supplied, highest first, with correct per-cargo numbers.
- Route: fork `SuppliersWidget`/`ConsumersWidget` (about 300 lines) through the ContentCard wrapper or `IndustryCombinedStockGroupedCountsPlugin` (:768).
- Rating: M / med.

### 43. Industries tab shows starving processors
- Friction: the Workload cell is blank at 0 % (statistic_industries.tl:278), so an unsupplied processor looks like a raw producer.
- Change: "0 %" when the industry has inputs; raw producers sort below.
  - Optional: "Connected / Starving" quick filters (`industry_util.isIndustryConnected`, main/industry_util.tl:541-556).
- Route: port the module return (:490, about 490 lines).
- Rating: M / med.

### 44. Account tooltip shows debt
- Friction: the Account tooltip repeats the balance in another format (game_bar.tl:243). Debt is 2 clicks away.
- Change: "$12.3M · Debt $40M (2 of 4 loans), $1.1M/month in loan payments".
- Route: game_bar.tl:243 is the only caller of `api.util.formatMoneyAlt`. Wrap it if `api.util` is writable; otherwise a 1532-line game-bar fork, which is not worth it.
- Rating: E (if writable) / med.

### 45. ConstructionWindow tabs: own label per station
- Friction: `getSubconstructionDescriptionAndSortKey` uses `getCarriers(stationGroup, -1, -1)`, which spans the whole group (make_entity_window.tl:60-90). Combined rail+bus constructions get identical tab labels, and sort keys add up.
- Route: fork `ConstructionWindow` (:117-276) plus the helper (about 220 lines), and pass the station index.
- Rating: M / med. Needs in-game check that such stations share a group.

### 46. Store Table layout: running cost and lifespan columns
- Friction: no "lifespan" anywhere in the store (grep). The Table layout, the only side-by-side view, has no running-cost or year column (vehicle_store_table.tl:345-470).
- Change: two more familiar columns.
- Route: fork `VehicleStoreTable` (587 lines, module return). This fixes B-V1 too.
- Rating: M / med.

### 47. Calendar speed shown only when not 1x
- Friction: a slowed or frozen calendar is visible only in Weather & Time (game_bar_widgets.tl:337-404), so a frozen date looks like a bug.
- Change: when the factor is not 1x, the date shows the vanilla `calendar_speed.tga` icon and "0.25x"/"Paused".
- Route: wrap the exported `game_bar_widgets.CalendarDisplay` (:269).
- Rating: E / low-med.

### 48. Tram and bus-lane options in the bottom bar
- Friction: Catenary and Symmetry have no `location` (tools/tram_track_tool.script.tl:24-52, bus_lane_tool.script.tl:17-26). A second, non-movable Settings window opens for two buttons, while Underground sits in the bottom bar.
- Route: in the `forEachDefinition` wrapper, set `param.location = Toolbar` for those two actions. Check the width.
- Rating: E / low-med.

### 49. Achievements tab shows whether they can be earned
- Route: wrap the exported `savegame_react_util.ScrollableAchievementsList` (:1551) and prepend the vanilla "Achievements cannot be earned." tape (savegame_react_util.tl:1486-1497) plus "x / y unlocked".
- Rating: E / low-med.

### 50. Discard junk one-stop lines (debatable)
- Friction: any station click in MAIN mode creates "Line N" at once (manager_window.tl:311, 6691-6716), and it stays behind as a one-stop line with a problem marker.
- Change: a line created in this session that still has one stop and no vehicles is discarded when deselected.
- Route: capture `commonParams` and send `makeLineDestroyCmd` with the mission guard (manager_window.tl:6810).
- Rating: M / med. The user decides.

### 51. Line search by station name (flag: big fork)
- Friction: the search matches line, cargo and depot names only (manager_window.tl:2525-2580), and default names are "Line N".
- Route: the local `LineAndDepotList` means forking `ManagerWindowContent`, effectively the 8.5k-line file. Not recommended unless the LVM is forked for other reasons.
- Rating: H / high.

### 52. Cargo waiting at cargo terminals (flag: big fork)
- Friction: `TerminalStops` receives `isCargoTerminal` but ignores it, and counts use passengers only (station_group.tl:314, 705-707).
- Route: fork `StationGroupWindowContent` (about 1,069 lines). Flag it; it was rejected as a new card, and this is the in-place alternative.
- Rating: H / med-high.

## 3. Notes on done or decided work found during the audit

- Configure → module tab: see #13. A vanilla index bug makes the naïve `constructionMenuSetTab{sublistId}` unreliable in the Modules menu.
- Rail+Tracks merge:
  - If entries were *moved*, the Tracks game-bar button greys out (game_bar.tl:608-613, 631). Mirroring avoids that.
  - In the merged menu, track and station params share one bucket per menu (construction.tl:1454) and both use the key `height` (construction_react_util.tl:2240-2265 vs 851-868). Elevated track at +10 m then places the next station at +10 m. If that is unwanted, set `resetOnDefinitionChange=true` on the construction `height` param through the `forEachDefinition` wrapper. Needs in-game check.
- Statistics Lines tab: our bug and per-frame cost, see #2.

## 4. Small vanilla bugs that can be fixed invisibly

"Route" names the cheapest way. "fork only" means the bug sits in a local recipe and is worth fixing only together with a fork done for other reasons.

| Id | Where | Bug | Fix / route |
|---|---|---|---|
| B-T1 | statistics/statistics_react_util.tl:353 | `warnIdsLess` used as an equality function, so a fixed problem never clears; the `userParam` state is stale too | #1, replace `ProblemsCell` |
| B-T2 | statistics/statistic_stations.tl:242-245 | Utilization sorts by `{used, capacity}`, not by the shown ratio | port (#18) |
| B-T3 | statistics/statistic_stations.tl:222-225, 367-368 | `GetTownOfStationGroup` returns -1, not nil, so `getEntityName(-1)` is called for multi-town groups | `town ~= -1`; port |
| B-T4 | statistics/statistic_vehicles.tl:312-314 | Age sorts by `purchaseTime`, so the direction is inverted | port (#17) |
| B-T5 | statistics/statistic_depots.tl:206-208, 85 | Usage shows used/pool but sorts by used; `"{used} / {poolSize}"` is not wrapped in `_()` | port (low) |
| B-T6 | statistic_towns.tl:78, statistic_industries.tl:339, main/hud_icon_toolbox.tl:67, 82 | `tostring` instead of `lang_util.formatInt`, so there are no thousands separators | port, or `HudIconMasterGame` (do not replace; campaign uses it) |
| B-T7 | statistic_industries.tl:278, 372-380 | 0 % workload hidden; Workplaces sorts by absolute count | port (#43) |
| B-L1 | line_vehicle_mgmt/cargofilter_window.tl:863 | A typed max stop time ≥ 601 s becomes "unlimited" (slider mapping applied to typed input) | `CargoFilterWindow` fork (913) |
| B-L2 | line_vehicle_mgmt/manager_window.tl:6851-6868 | `moveStop` skips `autoLoadConfig` | #39 |
| B-L3 | line_vehicle_mgmt/manager_tooltips_util.tl:240 | `VMDefault` uses `_()` instead of `nGetText`, giving "send 1 vehicles" | wrap the exported `VMDefault` |
| B-L4 | line_vehicle_mgmt/manager_window.tl:6836 | `makeLineManagerState(...)` result discarded (dead statement meant to clear the selection) | fork only |
| B-L5 | line_vehicle_mgmt/line_manager_panel.tl:253 | Terminal compared modulo the stop count, so path-problem markers land on the wrong terminals | blocked by celmi (`LineManagerPanel`) |
| B-L6 | line_vehicle_mgmt/first_stop_to_send/scheme_firstcargocompatiblestop.script.tl:16 | `stopIndex + waypointCount` gives the wrong first stop on lines with waypoints | own scheme resource; needs check |
| B-L7 | line_vehicle_mgmt/manager_window.tl:4738-4747 | Failed sends buffered even with `doNotBuffer`, then replayed later, so a vehicle can be pulled back | fork only; needs check |
| B-L8 | line_vehicle_mgmt/cargofilter_window.tl:335, 345 | `cargoLoad` paired with input cargo (`autoLoadConfig` pairs it with output), so the "No Compatible Stock" hint can be wrong | cargo window fork; needs check |
| B-V1 | line_vehicle_mgmt/vehicle_store_table.tl:254-256 | `mission.vehiclesBought` fired every frame for every row in Table layout, so a buy task completes without buying (mission_x/…/buy_vehicle.tl:11-19) | `VehicleStoreTable` fork (#46) |
| B-V2 | entity_window/maintenance_station/maintenance_station_eow.script.tl:160-165 | Balance card condition reads fields the window never fills, so it never shows | patch the condition module field; may be intentional |
| B-V3 | line_vehicle_mgmt/vehicle_store_window.tl:859-869 | `canBuyState` computed every frame per row and never rendered | fork only |
| B-V4 | line_vehicle_mgmt/vehicle_store_window.tl:1546-1552 | Buy sound plays before the affordability check | fork only |
| B-V5 | line_vehicle_mgmt/manager_window.tl:5277, 5256 | Modify toggle state uses `selectionReplacableState`; LVM Modify passes `transportModes = nil` | fill modes in the `VehicleStoreWindow` wrapper |
| B-V6 | line_vehicle_mgmt/vehicle_store_window.tl:3896 | `totalPrice = numDuplicates * totalPrice` multiplies the running total (latent) | fork only |
| B-V7 | vehicle_store_window.tl:4655-4669; vehicle_react_util.tl:363, 405 | Buy without `onFail`, Replace without a callback: failures are silent, and the text says "Could not clone" | #16 patch |
| B-V8 | line_vehicle_mgmt/line_util.tl:1792-1801 | `getBestDepotForLine` overwrites `pos` per stop, so the last stop is used (a centroid was probably intended) | wrap; needs check |
| B-V9 | line_vehicle_mgmt/manager_window.tl:5595-5605 | "Send to {depot}" tooltip names a depot that is ignored. `jumpToDepotEntity` teleports, so it is not a fix | wrap the tooltip text |
| B-E1 | entity_window/station_group/station_group.tl:391 | Via rows use `stopsAndQualitiesForLine[1].hasOverlength` instead of `stopAndQuality.hasOverlength` | fork only |
| B-E2 | entity_window/station_group/station_group.tl:677 | Destination tooltip iterates `pairs()`, so stops are in random order | fork only |
| B-E3 | entity_window/industry/industry_eow.script.tl:187 ff. | Supply counts keyed by entity, not by row | #42 |
| B-E4 | entity_window/make_entity_window.tl:60-90 | Carriers taken from the whole group; sort keys accumulate | #45 |
| B-E5 | entity_window/town/town.tl:604, 1023, 1149 | Suppliers flow flag never reset, so the arrows and the table get out of sync | ContentCard wrapper |
| B-E6 | entity_window/industry/industry.tl:418 | Industry Configure button tagged `entityWindow.stationGroup.configure` | `ActionButtonBar` wrapper can retag |
| B-E7 | entity_window/line/line_eow.script.tl:80 | `LineTransported` registered under the name "LineRate", so the `R::LineRate` CSS matches both | fork only (cosmetic) |
| B-E8 | entity_window/line/line_eow.script.tl:139 | `math.floor(age/lifespan)` makes the lifetime tooltip say 0 % until the end | fork only (local `LineTableCellAge`) |
| B-E9 | main/react.lua:804 | `iaHandlerExtended` reads undefined `promptTextOverride` | base framework; leave |
| B-C1 | construction/construction.tl:2809-2821 | sublistId handler mixes data index and shown position | #13 workaround |
| B-C2 | construction/construction.tl:587 | Search uses Lua patterns: `(`, `[`, `%` throw "malformed pattern" | check the severity in game; fragile `TextInputField` wrapper, or fix in a global search |
| B-C3 | construction/tools/town_builder_tool.script.tl:167 | Map-editor town builder values `{"no","res","com","ind"}` are untranslated | `forEachDefinition` wrapper, reusing existing strings |
| B-C4 | main/menu_category_util.tl:289 | Filter chip passes the old state to `onFilterChange` (known F20) | not worth it alone |
| B-F1 | game_mechanics/company/company_util.tl:178-179 | "Obsolete With Rank" prints `minRank` (latent; mods only) | #7 patch |
| B-F2 | game_mechanics/finance/loan_util.tl:67-74 | Initial "Small" slot can hold a large loan | sim side; cosmetic |
| B-F3 | game_mechanics/finance/loan.script.tl:172-194 | `allCmdsOk` checked before the async callback, so the loan is removed even if the debit fails | sim script; needs check |
| B-F4 | game_mechanics/finance/finances_charts.tl:409; finances_assets.tl:458 | Signature expects a string but gets `{tabValue=…}`, so focus resets on every re-render | wrap and pass `param.tabValue` |
| B-F5 | entity_window/perk/perk_eow.script.tl:37-40 | `descMetadata` may be nil | wrap the exported `PerkBasicsPlugin` |
| B-S1 | menu/save_game_page.tl:75-79 | With text in the save filter, saving under an existing non-matching name overwrites without asking | `SaveGamePage` fork (#20b) |
| B-S2 | game_mechanics/celebrations/celebration_react_util.tl:207-218 | nil index when every queued celebration is obsolete | #38 |
| B-S3 | main/pause_menu.tl:181-208 | Quit rack buttons not disabled during a save | #14 |
| B-S4 | menu/savegame_react_util.tl:1105-1121 | Double-clicking a details row ignores the edited mods and gameplay settings | fork only (700-line recipe) |
| B-S5 | menu/savegame_react_util.tl:1047, 1060 | Gameplay tab never gets the "*" changed marker | fork only |
| B-S6 | menu/mod_selector_page.tl:597-602 | Enter does not save a mod preset | wrap the module return; low |
| B-S7 | music_player/music_player.tl:52, 61-69, 233 | Mute is lost on reopen, and the mute button is then disabled | 287-line fork; low |

Not moddable (main-menu only; there is no replacement pass outside `bootstrap_game.tl`):
- the "Downloading Mods" dialog's misplaced `onBackChoiceIndex` (main_menu.tl:714)
- no "Reset to Default" for remembered new-game gameplay settings (advanced_settings.tl:569)

## 5. Considered and rejected (so they are not re-proposed)

- Bulldozer confirmation dialog: no engine veto exists; #10 is the substitute.
- Sticky bridge/tunnel choice across menus: with Rail+Tracks merged it already survives inside the menu, and stickiness worsens the stale-slow-bridge case. #27 instead.
- Persisting height, bend or snapping: these are safety resets, and keeping them would surprise players.
- Persisting Underground: `resetOnMenuClose` cannot work, because the param lives in bucket -1 (construction.tl:1817-1831, 1879-1881).
- "Honour the clicked depot" for send-to-depot: `jumpToDepotEntity` teleports, so it would be a cheat. Fix the tooltip instead (B-V9).
- Auto-applying company rank: it skips the vanilla unlock ceremony. #7 instead.
- Camera bookmarks or jump-back, direct speed keys, quickload, quicksave toast:
  - New hotkeys and new UI are not possible, and the speed logic is local (main/game.tl:617).
  - The engine probably shows its own save indicator (main/internal.css.lua:68-84); check before building anything.
- Remembering finance carrier expansion, statistics expand/shrink, search and carrier toggles: each needs a 700+-line fork for little gain.
- "Take a loan" link in the store's "Not enough money": new UI outside the screen's purpose.
- Notification changes of any kind: out of scope by the v2 rule (#37 is reading-only presentation).

## 6. In-game checks needed before building

1. Is `app` writable (#14), and is `api.util` writable (#44)?
2. Does the LVM `commonParams` metatable proxy survive re-renders and catch row clicks (#15, #32, #39, #50)?
3. Does the bulldozer proposal's `toRemove` contain the station construction (#10)? Does the native tooltip already show affordability and refund (#22)?
4. Which Modules tabs are empty for which station types (#13)?
5. Do passengers board when the stop's passenger load flag is false (#12)?
6. Does mod CSS load, and can it override `!invisible` in the log (#37)?
7. Is `getGuiSaveData(modId)` with a non-empty id saved with the game (#35, #36)?
8. How do TF3 rail models declare `transportModes` versus `engineTransportModes` (#25)?
9. Ticket price multiplier semantics (#41), and how bad the search pattern error is (B-C2).
10. Shared `height` param in the merged Rail menu (section 3).
11. How celmi_timetables replaces `LineManagerPanel`: wrap or fork? Does its stop row still call `line_react_util.LineCargoDisplay` (#21)?

## 7. Corrections to the inventory

- The pause menu does pause the game (`setInGameMenuPause`, pause_menu.tl:263-268).
- Celebrations have a Settings toggle (settings_page.tl:525-528).
- New games already remember the last mods, mod params, gameplay params, start year and terrain generator (new_game_react_util.tl:82-200). Mod presets exist (mod_selector_page.tl:1581-1735).
- Town rating bars do not open layers: `onClickEvent` has no reader (town_util.tl:654-704). The town window tabs set the layer themselves.
- The vehicle store full fork is about 4,680 lines, not about 2.5k (D6).
