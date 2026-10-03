# UX Overhaul — plan

Goal: the player sees the state of the network **without clicking** and can act on it **where they see it**, in the fewest clicks. This plan is based on the code-level inventory in [inventory/](inventory/README.md).

## 1. Design principles

1. **Status costs 0 clicks.** Problems, money trends and network health are always visible.
2. **Diagnosis costs 1 click.** One click on a status chip or an entity shows the cause, with no hovering, tab hunting or second window.
3. **The action sits next to the status.** Wherever a problem is shown, the fix is a button right there, e.g. "+1 vehicle" next to an overloaded line or "Replace" next to an old vehicle.
4. **Never lose context.** Lists and detail windows stay open side by side, and following a link doesn't close the window you came from.
5. **Safe bulk actions.** Every list allows multi-select. Destructive bulk actions ask for confirmation once.
6. **Add first, replace last.** Use extension-point plugins wherever possible. A few small *wrapping* recipe replacements are allowed; whole-file forks only when the gain is large. Each feature can be switched off on its own.

## 2. Baseline vs target: the tasks that matter

| # | Task | Today (from inventory) | Target | Feature |
|---|---|---|---|---|
| T1 | "Is anything wrong in my network?" | 2–6 clicks across Statistics tabs and the log; most problem types are hidden by default | **0** (glance at status strip) | A1, A3 |
| T2 | Find the lines that lose money | 4 clicks (Statistics → Lines → sort) or 1 click per line in the Line Manager | **0** to see the count, **1** to see the list | A1, C1 |
| T3 | Add N vehicles to a line | 5 + (N−1) in the Line Manager; from the line window ≥ 6 plus a window switch | **1 per vehicle** from line window, Line Manager row or overview | B1, D1 |
| T4 | Replace the old vehicles of a line | 5 + 2N plus a trip to Statistics (no age shown in the Line Manager) | **3** (filter "old" → select all → Replace) | C2, D2 |
| T5 | Why is this station overcrowded? | 2 + n clicks plus hovering; cargo not shown | **1** (station window card) | B2 |
| T6 | What does this industry need, and who supplies it? | 2–4 clicks; section collapsed and reset on reopen | **1** | B3 |
| T7 | Why isn't this town growing? | 2–10 tab clicks; ratings shown only as colours | **1** | B4 |
| T8 | Rebalance N vehicles between lines | N + 5 | **3** | C2 |
| T9 | Full load on all k stops of a line | 2k + 1 | **3** | D4 |
| T10 | Look at a list and an entity at the same time | impossible (the list is hidden) | side by side | E1 |
| T11 | Build a rail line (stations, depot, tracks, signals) | 3–4 switches between the Rail and Tracks menus | **0–1** | F1 |
| T12 | Save to the current save | 4 clicks (with the overwrite dialog) | **1** | A2 |

## 3. Architecture

```
src/ux_overhaul/content/ux_overhaul/
  core/            pure Lua, no engine access → offline specs against the mock
    metrics.lua      line/vehicle/station aggregates (balance, utilization, age%, problems)
    problems.lua     unify notifications + own detectors into one ranked problem list
    format.lua       money/percent/time formatting, colour thresholds
    settings.lua     feature flags (mod params) + per-save GUI settings (api.gui.game.get/setGuiSaveData)
    compat.lua       startup self-check: required base modules, recipes, fields exist → clear log line, feature off
  engine/          thin adapters api.engine.* → plain tables (the only place that touches the engine API)
  gui/
    entry/           ModEntryPointExtension plugin: event hub ("uxo.*" events), opens our windows
    status/          GameBarInfoDisplayExtension plugins (status strip)
    launcher/        MainModButtonAreaExtension plugins (quick-launch row) + RadialMenuExtension
    overview/        "Control Center" tool window (tabs Problems / Lines / Vehicles / Stations)
    eow/             entity-window cards (line, station, industry, town, vehicle, town building)
    lvm/             react-replacement-config wrappers for the Line/Vehicle Manager
    shell/           react-replacement-config for ToolStack / InspectorSelector (window behaviour)
  notifications/   game script (*.gs.lua) + notification type resources for the new detectors
  construction/    menu_category / construction_tool data overrides
```

- **Recipe names** are prefixed `Uxo…`, events `uxo.*`, and all variables are `local`. Global CSS selectors and event names are shared with other mods.
- **Data:** read with `engine_react_util.useStepStateTimer`, at least every 0.5–1 s; aggregates over the whole network use `useStepStateParallel`. Results are memoised by `api.engine.getRevision()`.
- **Actions:** use the base helpers where they exist (`line_util.sendVehiclesToDepot`, `vehicle_react_util.onBuy`, `duplicateVehicles` event); otherwise call `api.cmd.make*Cmd` with a GUI-side callback. `gameCtx.filters.protectedEntities` and `disableFeatures` are respected, so campaign missions keep working.
- **Navigation:** go to base windows only through their own events (`selectEntity{stack=true}`, `openVehicleManager{…}`, `openStatisticsWindow`, `openFinanceWindow`, `constructionMenuSelectTabForConstruction`).
- **Never replace** `GameUIRoot`, `HudIconMasterGame` or `PerkHudIcon`; campaign missions replace the last two.
- **Testing:**
  - **Offline:** specs for `core/` and `engine/` adapters against the mock.
  - **In-game:** the template's testbench, extended with a GUI step. `guiUpdate` fires `uxo.*` events and checks `api.gui.byId.isVisibleRecursive("uxo.…")`, giving PASS/FAIL. Screenshots come from `api.gui.camera.takeScreenshot`.

## 4. Feature backlog

Effort is rated **E** (easy: plugin or data), **M** (medium: wrapping replacement) or **H** (hard: fork of a large recipe).

### A — Status at a glance (shell)
| Id | Feature | Effort |
|---|---|---|
| A1 | **Status strip** in the game bar. Shows cash-flow (this month / last month, red/green), loan, number of loss-making lines, number of lines with problems, vehicles without a path, vehicles past their lifespan. Each chip is clickable and opens the Control Center on that filter. | E |
| A2 | **Quick-launch row** next to the layer buttons: Control Center, Finances, Company, Vehicle Store, Notification log, "next problem" (focuses the camera on it and opens it), speed 1×/2×/4×, Save (overwrite the current save). | E |
| A3 | **Problems visible by default.** Un-ignore the vanilla problem types for new and existing saves, through a one-time `updateIgnoredTypes` event. | E |
| A4 | **New detectors**, which add new notification types: unprofitable line, low cash, vehicle past lifespan, line without vehicles, vehicle idle in depot. They automatically show up in the log, the HUD, entity windows and statistics. | E–M |
| A5 | Badge with the problem count on the vanilla notification button. | M (`NotificationButton`) |

### B — Act where you look (entity-window cards, all plugins)
| Id | Feature | Effort |
|---|---|---|
| B1 | **Line window: "Stops & vehicles" card.** Lists the stops in order with waiting passengers *and cargo*, links to the stations, load factor and frequency as text, overlength warning. Buttons **+1 / −1 vehicle** (clone the newest one; send the oldest to the depot and sell it on arrival). | E |
| B2 | **Station window: "Overview" card** (the slot is empty in vanilla). For each line: frequency, waiting count and load. Waiting cargo per type. Destinations listed inline instead of on hover. Nearby towns and industries as links. | E |
| B3 | **Industry window: "Supply summary" card.** For each cargo: amount moved last period, connected vs possible partners, nearest unconnected partner with its distance, links. | E |
| B4 | **Town window: "Growth blockers" card.** The 8 ratings sorted worst first, with value and reason; percentage to the next level as text; missing supplies. | E |
| B5 | **Vehicle window: labelled quick actions.** Open line, Clone into line, Send to depot (+sell), Replace with the newest model, Follow. Destructive actions ask for confirmation. | E |
| B6 | Cross-links: town building → its town; vehicle → its stop list. | E |

### C — Control Center (one overview window, our own tool window)
| Id | Feature | Effort |
|---|---|---|
| C1 | **Problems tab.** One ranked list of all problems (vanilla notifications plus A4), grouped by type with counts. Per row: jump (stacked), fix action (+vehicle, replace, send to depot) and dismiss/snooze. Bulk dismiss by type. | M |
| C2 | **Lines tab.** Sortable columns: carrier, vehicles (number), utilization, frequency, 12-month balance, trend (this year vs last), problems. Quick filters: *losing*, *problems*, *under/over capacity*, *no vehicles*. A totals row. Per-row actions: +1/−1 vehicle, open in the Line Manager, open the line window. Multi-select for bulk actions. | M |
| C3 | **Vehicles tab.** Age as % of lifespan, condition, balance, state, line. Quick select: *past lifespan*, *poor condition*, *stopped*, *no path*. Bulk Replace / Send to depot (+sell) / Move to line (the rebalance in T8). | M |
| C4 | **Stations tab**, including stations without lines (idle upkeep), with cargo delay. | M |
| C5 | Filters, sort order and the selected tab are kept per save (`setGuiSaveData`). | E |

### D — Line/Vehicle Manager upgrades (replacements, so behind feature flags)
| Id | Feature | Effort |
|---|---|---|
| D1 | **Row badges** through a wrapper around `line_react_util.ManagerNotificationWidget`, which is drawn in every line, depot and vehicle row. Line rows get carrier, vehicle count, utilization, balance, the problem reason and a "+1" button. Vehicle rows get age %, condition, the problem reason and whether the vehicle is stopped. | M (wrap, small) |
| D2 | **Vehicle list:** sortable, with columns and quick-select buttons (*old*, *worn*, *problem*), by replacing the exported `VehicleList`. Also fixes the vanilla sort-by-line bug. | M |
| D3 | **Remember** the line and mode when the Line Manager is reopened, and ask for confirmation before cloning more than one vehicle (`ManagerEntryPoint`). | M |
| D4 | **Stop configuration for the whole line:** "apply to all stops", "reset to automatic cargo", and an auto/manual indicator (`CargoFilterWindow`). | M–H |
| D5 | Overlength warning in the stop row (`LineCargoDisplay` wrapper). | M |
| D6 | Store defaults: newest model first and preselected (`VehicleStoreWindow`). | H (fork; later) |

### E — Window behaviour
| Id | Feature | Effort |
|---|---|---|
| E1 | **Side-by-side tool windows.** Statistics, the Line Manager, Finances and the Control Center can be open together, and opening an entity window no longer hides the list. This replaces `ToolStack` (about 260 lines copied) with a whitelist. | M |
| E2 | **A map click keeps the tool windows open**; a modifier key keeps entity windows too (`InspectorSelector` / `ViewManager`). | M |
| E3 | **The Line Manager opens stacked**, so the entity window you came from stays open. | M |

### F — Construction
| Id | Feature | Effort |
|---|---|---|
| F1 | **One Rail menu** (stations, depots, tracks, signals, tools) and **one Road menu**, by changing the `menu_category` data. | E |
| F2 | Fastest / newest track and road listed first, through a patch of `getTrackDefinitions` / `getStreetDefinitions`. | M |
| F3 | "Configure" opens the relevant module tab (tracks/platforms) via `constructionMenuSetTab{sublistId}`. | E–M |
| F4 | **Construction search across all menus** (type, then Enter jumps to the item) via `constructionMenuSelectTabForConstruction`. | M |
| F5 | Demolish button in station and depot windows, with a confirmation. | M |
| F6 | Hide obsolete eras and items through a merged `setMenuFilter`. | E |

### Not feasible (engine limits, documented so we don't promise them)
- New rebindable hotkeys; input actions are hard-coded in the engine. Launchers are buttons, radial-menu entries and the quick-launch row instead.
- General undo, a parallel/double-track builder, timetables.
- Changing list-item rendering in the construction menu without forking the 5,000-line `construction.tl` (not planned).

## 5. Phases

### Phase 0 — Spikes (verify the engine assumptions in-game) — **done 2026-10-03**

Result (`make test-ingame`, 7/7 PASS): game-bar plugin, mod button plugin, mod stylesheet, wrapping
recipe replacement, own window opened via a mod event (also from `api.gui.fireReactEvent`), town
entity-window card, `setGuiSaveData` round trip. Lessons:
- **Every recipe must return a layout (`BoxLayout`) as root.** Anything else aborts the *whole* game
  UI (`ReactFramework::Load() failed`). `spec/ingame/run.sh` now fails on that log line.
- `api.gui.camera.takeScreenshot` renders without UI; `byId.getSize` is 0×0 for non-windows. GUI
  checks use `byId.isVisible` and CSS-driven probes instead.
- Still open, verified during the MVP when needed: station-window card (needs a built station), GUI
  save data across save/load (C5), mod params from GUI code (feature flags), `useInputAction` reuse.

Original spike list:
Build a throw-away `uxo_spike` feature set and extend the testbench with GUI assertions. Each spike gives PASS/FAIL in `make test-ingame`:
1. A `react-plugin ::GameBarInfoDisplayExtension` from a staging mod is discovered, and its `.script.lua` loads.
2. A `ModEntryPointExtension` handles `uxo.open` and opens a `builtin.Window` / tool window; a `MainModButtonArea` button fires the event.
3. A `react-replacement-config` wrapping `line_react_util.ManagerNotificationWidget` with `CallOriginalRecipe` takes effect.
4. The mod's `*.css.lua` is applied.
5. A `StationGroupEowExtensionPoint` plugin renders.
6. `setGuiSaveData` survives saving and loading.
7. Mod params (feature flags) can be read from GUI code; otherwise flags fall back to the Control Center settings in `setGuiSaveData`.
8. Optional:
   - `addModifier("loadGameRes")` to reorder or hide base plugins;
   - `react.useInputAction` on an existing input action;
   - `makeGameSetSpeedCmd(8)`.

The outcome updates the effort ratings above and the skill's `engine.md`.

### Phase 1 — MVP "See and act" (first mod.io release)
A1, A2, A3, A4 (unprofitable line, past lifespan, line without vehicles), B1, B2, B5, C1, C2.
→ Covers T1, T2, T3, T5 and T12. Uses only plugins and our own windows; **no vanilla recipe is replaced**, so the risk of conflicts with other mods is minimal.

### Phase 2 — Overview depth
C3 (bulk replace and rebalance), C4, C5, B3, B4, B6, A4 (low cash, idle in depot), A5.
→ Covers T4, T6, T7 and T8.

### Phase 3 — Fix vanilla friction (replacements, each behind a flag)
D1, D2, D3, D5, E1, E2, E3.
→ Covers T10 and makes the Line Manager itself readable.

### Phase 4 — Construction
F1, F3, F6, then F2, F4, F5.
→ Covers T11.

### Later / maybe
D4, D6, command palette (jump to any line, station or town by typing), notification log columns and search, celebration throttle, shortcut cheat-sheet.

## 6. Quality gates per feature
- Offline spec for every `core/` module, plus an in-game scenario (testbench) for every GUI surface and every action.
- `make lint test test-ingame validate` must pass, with no new `Lua error` lines in `stdout.txt`.
- Performance: the status strip and Control Center are measured on a large save. The target is no visible frame drop; that means `useStepStateParallel` for anything over all vehicles.
- The startup `compat.lua` check passes on the current game build. When a required base symbol is missing, the dependent feature switches itself off and logs a single `[uxo] disabled <feature>: <reason>` line.
- English and German strings from the start (`strings.lua`).

## 7. Compatibility notes (scanned 2026-10-03)

Installed community mods that use the same hooks:
- **celmi_timetables:**
  - replaces `line_manager_panel.LineManagerPanel`;
  - adds plugins to the game bar, the mod button area, the radial menu, and the Line, Station and Vehicle windows.
  - → We **must not replace `LineManagerPanel`**, which rules out D4/D5 via that recipe. We put our cards at a different `order`.
- **zhenya_auto_assign_terminals:**
  - replaces `popover_react_util.PopoverWindowContent` and a scroll container;
  - monkey-patches `line_util.makeLineActionDescriptor` and `builtin.Button`.
  - → Avoid those recipes. Its patching confirms that patching module tables works.
- **auto_line_namer:** only `rename_scheme` data and a game script, so no conflict.

## 8. Risks
- **Game updates:** we depend on internal module paths and exported recipes, which are not a public API. Mitigations: `compat.lua`, re-running `tools/extract_game_sources.sh` and diffing after every patch, and keeping replacements few and wrapping.
- **Mod conflicts:** only one mod can replace a given recipe. Phase 1 has no replacements; phase 3 replacements are behind flags and listed in the mod description.
- **Performance** on large networks: use parallel/timer hooks, memoise per revision, and slice detector scans the way vanilla does.
- **Save compatibility:** phase 1 adds a game script, needed for A3/A4. `severityRemove` must be checked; removing the mod should only leave unused notification entries behind (verify).
