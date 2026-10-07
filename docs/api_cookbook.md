# TF3 data and action API cookbook (for GUI mods)

Derived only from the extracted game source of the build in `.game/game/` (see `docs/inventory/README.md`).
Every snippet is copied from base code and converted from Teal to plain Lua (type annotations and `as X` casts
removed; `api.type["enum"]` written as `api.type.enum`). All file:line refs are relative to `.game/game/`
unless a section declares a short form (`G/` = `gui/gui/`, `LVM/` = `gui/gui/line_vehicle_mgmt/`,
`EOW/` = `gui/gui/entity_window/`, `NM/` = `game_mechanics/game_mechanics/notifications/`, `T/` = `NM/types/`).
Bare names like `statistic_lines.tl:120` refer to the file in the module folder named in the same subsection.
"NOT FOUND" = searched for and absent. "Verify in-game" = follows from code but was not run.
These are internal modules with no stability guarantee; re-check after every game patch.

Contents: [0 Ground rules](#0-ground-rules-threads-polling-cost) · [1 Money](#1-money--finance) · [2 Lines](#2-lines) ·
[3 Vehicles](#3-vehicles) · [4 Stations](#4-stations-station-groups) · [5 Notifications](#5-notifications) ·
[6 Actions](#6-actions) · [7 Formatting](#7-formatting-helpers) · [8 Widgets](#8-reusable-base-gui-widgets)

## 0. Ground rules: threads, polling, cost

**States / threads** (from the API headers):
- `api.engine.*` is "read-only access to the entire engine state ... accessible from both the GUI State and the Engine State" (`apidef/api/engine.d.tl:3-4`). GUI recipes may call it directly; base GUI code does so everywhere.
- `api.cmd.*` works in both states. From the GUI state "commands are executed in the next simulation step ... The callback function will be called the frame after the command has been executed" (`apidef/api/cmd.d.tl:2-9`). In the engine state (game scripts) they run immediately and the callback fires immediately.
- Some `api.gui.*` / `api.util.*` functions are marked "Only available in GUI thread" (e.g. `apidef/api/util.d.tl:174-202`, `apidef/api/gui.d.tl:784,866,897-903`).
- Mod recipes run in the GUI react Lua state (`Lua_React_Game`). Plain Lua, no Teal needed: the snippets below are the base Teal code with type annotations and `as X` casts removed.

**Polling hooks** (`gui/gui/main/engine_react_util.tl`, types in `engine_react_util.d.tl:3-49`):

| Hook | What it does | Ref |
|---|---|---|
| `useStepStateTimer(getFromEngine, interval=0.5, equals=table_util.deepEquals)` | calls `getFromEngine(old)` every `interval` real seconds (deferred via `react.onStepTimer` → `enqueueDeferredStep`), sets state only if not deep-equal | `engine_react_util.tl:126-157`, `main/react.lua:525-534` |
| `useStepState(getFromEngine, makeCommand?, equals?, onChange?, once?)` → `state, commit` | runs `getFromEngine` on every step (`react.onStep`); pauses while a committed command is in flight | `engine_react_util.tl:59-124` |
| `useStepStateTimerWithCommit(getFromEngine, interval, makeCommand?, ...)` | timer variant with commit fn | `engine_react_util.tl:159-201` |
| `useStepStateParallel(useFnName, params, finalize, ...)` | first value computed synchronously; afterwards every step `react.enqueueParallel(useFnName, params, join)` → `api.gui.react.enqueueParallelWorkItem` runs the fn on a worker; `finalize(result, params, old)` runs on the GUI thread next frame | `engine_react_util.tl:203-260`, `main/react.lua:56-65` |
| `useStepStateParallelSimple(useFnName, params, equals?)` | same, finalize = identity | `engine_react_util.tl:262-265` |

- `useFnName` format is `"<res path without ext>@<table>.<field>"`, resolved by `util.useFn` (`scripts/scripts/util.tl:5-29`; it registers the ref with `loaderHelper:useFn(ref)` and walks `game[<path>][<table>][<field>]`). Base example: `"::/game_mechanics/towns/town_util_parallel.script@town_util_parallel.getTownCapacityUsages"` (`gui/gui/entity_window/town/town_eow.script.tl:32`). The worker module returns `{ town_util_parallel = town_util_parallel }` and its functions copy userdata into plain Lua tables before returning (`game_mechanics/game_mechanics/towns/town_util_parallel.script.tl:298-314`, end of file).
- Base usage of parallel state is tiny: only the town window (`town_eow.script.tl:27,32,1110`). Statistics, LVM and game bar all use `useStepStateTimer` with the default 0.5 s (e.g. `gui/gui/statistics/statistics.tl:105-114` uses `react.onStepTimer(..., 0.5)`). So "scan all lines every 0.5 s on the GUI thread" is what the base statistics window does while open; a permanently mounted dashboard should use 1-5 s or a parallel fn.
- Cheap change detection: `api.engine.getRevision(entity)` (`apidef/api/engine.d.tl:1718`; used in `gui/gui/entity_window/view_manager.tl:145-208`).

Minimal mod recipe skeleton (plain Lua, a recipe must return a layout as root):
```lua
local react   = require "::/gui/main/react.lua"
local builtin = require "::/gui/main/builtin.lua"
local engine_react_util = require "::/gui/main/engine_react_util.tl"

local M = {}
M.UioMoney = react.RegisterRecipe("UioMoney", function(params)
  local money = engine_react_util.useStepStateTimer(function()
    return api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer()) -- nil = infinite money
  end, 1.0)
  return builtin.BoxLayout{ children = { builtin.TextView{ text = api.util.formatMoney(money:old()) } } }
end)
return M
```
(The PLAYER component has only `headquarters`, `apidef/api/engine.d.tl:847-852`; money comes from `api.engine.util.finance`, see §1.)

---

## 1. Money & finance

**Units.** Money is a plain `integer` in currency units (no ×1000 scaling): loans are created as
`math.random(...) * 1000000` = millions (`game_mechanics/game_mechanics/finance/loan_util.tl:198`) and passed straight
to `api.util.formatMoney(loan.amount)` (`finances_loan_gui.tl:270`, DefaultLoanCard). Time is an `integer` game time in ms
(`GameTime.gameTime`, `apidef/api/engine.d.tl:425-438`); intervals in base use the *default-speed* constants
`api.util.getDefaultDayDuration() / getDefaultMonthDuration() / getDefaultYearDuration()` (`apidef/api/util.d.tl:110-120`),
e.g. `loan_util.tl:120` converts a duration to "minutes" with `/ 60000`.
**Threads.** `api.engine.util.finance.*` is called both from GUI recipes (game bar, finance window) and from game scripts
(`loan.script.tl:47`, `achievements.script.tl:121,202`), so it is available on both sides.

### 1.1 Current balance (game bar "Account")
```lua
-- gui/gui/game_bar/game_bar.tl:216-221 (MoneyDisplay)
local balanceState, commitBalance = engine_react_util.useStepState(
  function()
    -- balance == nil means infinite money!
    return api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer())
  end, ...)
-- display, game_bar.tl:240-246
builtin.TextView{
  meta = { class = "font-scale-body, " .. (balanceState:old() ~= nil and balanceState:old() < 0 and "negative" or "neutral"),
           tooltip = api.util.formatMoneyAlt(balanceState:old()) },
  text = api.util.formatMoneyNumber(balanceState:old())   -- number only; the currency prefix is a separate TextView:
}
-- game_bar.tl:293: text = api.util.getAppConfig().moneyPrefix
```
- Signature: `getPlayersBalance(player) : integer`. It returns **`nil` when money is infinite** (sandbox/"no costs") (`apidef/api/engine/util.d.tl:858-861`). All formatters accept `nil` (`util.d.tl:56-68`).
- Cost: cheap; base polls it with `useStepState` (every step). Same call in `construction_react_util.tl:1226`, `vehicle_store_window.tl:3530`.
- Alternative (not used by base): component `api.type.ComponentType.ACCOUNT` → `Engine.Component.Account { balance : integer, loan : integer }` (`apidef/api/engine.d.tl:22-29`, `:1668`). No base file reads it; prefer `getPlayersBalance`.

### 1.2 Loans / debt / "max loan"
TF3 has no single loan amount + max loan like TPF2. Loans are discrete offers managed by a base game script
(`game_mechanics/game_mechanics/finance/loan.gs.lua`), at most `loan_util.maximalObtainableLoans = 4` concurrent loans
(`loan_util.tl:184-186`). "Max loan" = NOT FOUND.

Total debt (as shown in Finances → Overview "Debt" chart and Assets tab):
```lua
-- game_mechanics/game_mechanics/finance/finances_charts.tl:217-220 (DebtChart)
local currentValue = api.engine.util.headquarters.getCompaniesValue()
local currentDebt = currentValue.debt
local result = api.engine.util.finance.getDebtChart(player, config, currentDebt)
```
`CompanyValue { balance, totalAssets, debt : integer, numberOfLines, totalStations, railVehicles, ... }`
(`apidef/api/type.d.tl:108-141`; `getCompaniesValue` `apidef/api/engine/util.d.tl:901`). Assets tab polls it with
`useStepState` (`finances_assets.tl:462-465`). Cost: it aggregates the whole company, so poll it with `useStepStateTimer` ≥ 1 s in a dashboard.

Individual loans (read the base game script's state, exactly as the Loans tab does):
```lua
-- finances_loan_gui.tl:484-496 (LoanBoard)
local getLoanTableFromEngine = function()
  local scriptEntity = api.engine.system.gameScriptSystem.getEntityForGameScript("::/game_mechanics/finance/loan.gs")
  local gameScript = api.engine.getComponent(scriptEntity, api.type.ComponentType.GAME_SCRIPT)
  return gameScript.state      -- LoanTable { availableLoans = {Loan}, obtainedLoans = {Loan}, freeId }
end
local loanTableState, commit = engine_react_util.useStepState(getLoanTableFromEngine, nil, isEqual)
```
`Loan { type = "Small"|"Medium"|"Large"|"ExtraLarge"|"Custom", amount (money), duration (game ms), percentage (0.03..0.12),
lastPayDay, timesPaid (months paid), birthDay, cooldownUntil, id }` (`loan.d.tl:27-51`). Outstanding principal of an obtained loan:
```lua
-- finances_loan_gui.tl:274-275
local moneyToPayLeft = loan_util.getPaymentLeftoverRounded(loan.amount, loan.duration, loan.percentage, loan.timesPaid, 100)
-- full remaining principal + interest: loan_util.getFullLoanAndInterestPayBack(loan) -> loanAmount, interestAmount (loan_util.tl:169-176)
```
(`loan_util` = `require "::/game_mechanics/finance/loan_util.tl"`.) Taking/repaying: the GUI sends
`api.cmd.makeScriptingSendEventCmd("", "Loan", "Obtain", {newAvailable, loan})` / `("", "Loan", "Repay", {nil, loan})`
(`finances_loan_gui.tl:292,312`); `loan.script.tl:133-160` books a `JournalEntry.Type.LOAN` via `makeJournalBookAssetCmd`.
Loans are disabled when balance is `nil` (`account.tl:14-18`).

### 1.3 Cash flow per period (finance window "Finances" tab)
The finance table is per year, not per month: 4 columns, header strings supplied by the engine.
```lua
-- game_mechanics/game_mechanics/finance/finances_table.tl:570-578 (FinancesTable)
local makeTableState = function()
  local player = api.engine.util.getPlayer()
  local config = api.type.ChartConfig.new()
  config.count = 4
  return api.engine.util.finance.computeFinanceTable(player, config)
end
local isTableEqual = function(a, b) return a == b end
local tableState = engine_react_util.useStepStateTimer(makeTableState, nil, isTableEqual)   -- 0.5 s default
```
`FinanceData` (`apidef/api/type.d.tl:5695-5713`), each value list is one integer per column:
- `header : {string}` column titles; `total` → row "Earnings" (`finances_table.tl:629`); `balance` → row "Bank Account" (`:636`);
  `loan` → row "Debt" (negated, `:638-642`); `interest` → "Loan Interest" (`:625`); `loanBorrowing`, `loanRepayment`.
- `transport[carrier][key] = {..}`, `investment[key]`, `other`: iterate with `data:foreach_carrier(fn(carrier, t))`,
  `data:foreach_transport(fn(key, values), carrier)`, `foreach_investment`, `foreach_other`; `data:unfoldKey(key)` →
  `{Type, Maintenance, Construction}`; labels via `finances_util.getCarrierLabel/getKeyLabel` (`finances_util.d.tl`).
- Supports `==` (`equals`). Cost: moderate (journal aggregation); base runs it on the GUI thread with the 0.5 s timer, only while the tab is open.

Revenue/expense chart (Finances → Overview): `api.engine.util.finance.getAccountChart(player, config)` with `config.count = years`
(`finances_charts.tl:193-196`) → `ChartResult { xRange, yRange, series = {{{x,y}}}, xMarkers, yMarkers, numPotentialGroups }`
(`type.d.tl:5624-5640`), series 1 = Revenue, 2 = Expenses. Per-year buckets.

**Current/previous month cash flow: no base API or UI.** Nearest thing (derived; base uses the same call with
`maintenanceIncomeOnly = true` for lines/vehicles, `line_react_util.tl:621-626`):
```lua
-- calculateBalance(entities, startTime, endTime, maintenanceIncomeOnly, maintenanceType?) : integer   (util.d.tl:841-848)
local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
local month = api.util.getDefaultMonthDuration()
local player = api.engine.util.getPlayer()
local thisMonth = api.engine.util.finance.calculateBalance({player}, math.max(gt - month, 0), gt, false)          -- rolling 30-day-ish window
local prevMonth = api.engine.util.finance.calculateBalance({player}, math.max(gt - 2*month, 0), math.max(gt - month, 0), false)
```
Passing the player entity is unverified (the doc says "entities (having an account)"; the player has an account, see
`getAccountChart(player)`). Calendar month boundaries: no inverse of `getCalendarDate` exists; `GameTime.dates : {{integer, Date}}`
is undocumented; verify in-game. Also available: `calcIncomeSince(time, player) : number` and
`getLastIncomeTime(player) : integer` (game-script use in `achievements.script.tl:121,202-204`).

### 1.4 "Earnings" in the game bar
```lua
-- gui/gui/game_bar/game_bar_display_earnings_plugin/game_bar_display_earnings.script.tl:10-13, 19, 34
local makeState = function()
  return api.engine.util.finance.calculateEarnings(api.engine.util.getPlayer())
end
local earningsAndIsMapEditor = engine_react_util.useStepStateTimer(makeState)       -- 0.5 s default
local className = earningsAndIsMapEditor:old() >= 0 and "positive" or "negative"
text = api.util.formatMoney(earningsAndIsMapEditor:old())
```
`calculateEarnings(player) : integer` = "earnings from beginning of the year to now" (`util.d.tl:849-852`), i.e. calendar
year-to-date, same meaning as the "Earnings" row of the finance table. Tooltip `_("Total Earnings")`. Hidden in map editor
(`api.gui.game.isMapEditor()`). Cheap.

### 1.5 Time & date reading
```lua
-- game time (ms), used everywhere, e.g. line_react_util.tl:623-625
local gameTimeComponent = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
local toTime = gameTimeComponent.gameTime
local fromTime = math.max(toTime - api.util.getDefaultYearDuration(), 0)     -- base "last 12 months" window
-- calendar date as in the game bar, game_bar_widgets.tl:258-268 (polled with useStepState, game_bar.tl:1124)
local date = api.engine.util.getCalendarDate(gameTimeComponent.gameTime)     -- Date {year, month(1-12), day}
-- current year: api.engine.util.getYear() : integer   (util.d.tl:1033)
-- speed: GAME_SPEED component { speedup : integer (0 = paused), millisPerDay : integer (0 = paused) } (engine.d.tl:415-422)
local gameSpeed = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED)
```
Note: calendar speed is decoupled from simulation: `getYearDuration(millisPerDay)` / `getMonthDuration(millisPerDay)`
(`util.d.tl:100-108`) give the calendar-adjusted length; the base 12-month balance windows use the default year duration,
not the calendar one. Age-in-years style values should therefore divide by `api.util.getDefaultYearDuration()`.

---

## 2. Lines

Common facts for this section:
- All paths are relative to `.game/game/`. Snippets are base Teal with annotations and casts removed. `api.type["enum"].X` in Teal is written as `api.type.enum.X` in plain Lua (`enum` is a Teal keyword but not a Lua one).
- Every engine call below is a read from `api.engine.*`. The base calls these from GUI recipes, and `notifications.script.tl` calls the same `api.engine.util.line.*` functions from the engine-side game script. They work in both states.
- The base never uses `useStepStateParallel` for lines or stations. The town window is the only parallel caller. Statistics and the LVM use `useStepStateTimer` (default 0.5 s) or `useStepState` (every step), once per visible table cell.
- Money values are raw integers; pass them to `api.util.formatMoney`. Time values are game-time ticks (`GAME_TIME.gameTime`, integer); `api.util.getDefaultYearDuration()` = "game ticks per year" (`apidef/api/util.d.tl:118-120`).

### 2.1 Lines of the player
```lua
local keys = api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
```
- `gui/gui/statistics/statistic_lines.tl:380`. Returns `{Engine.Entity}` (`apidef/api/engine/system.d.tl:17-20`).
- Cheap: cached by the LineSystem. Statistics calls it every step (`useStepState(makeTableState)`, `statistic_lines.tl:379-389`).
- Other calls: `getLines()` returns all lines; `getLinesForStationGroup(sg)`; `getLineStops(sg) -> {{line, stopIndex0}}` (`system.d.tl:13-47`).

### 2.2 Name and color
```lua
local name  = api.engine.util.getEntityName(lineEntity)                                  -- string
local color = api.engine.getComponent(lineEntity, api.type.ComponentType.COLOR).color   -- Vec3f, 0..1
```
- Name: `statistic_lines.tl:258-260`.
- Color: `gui/gui/line_vehicle_mgmt/line_react_util.tl:271-287` (`ColorWidget`, polls with `react.onStepTimer` and compares with `:equals`) and `line_react_util.tl:589-594` (`LineColorPicker`).
- To recolor: `api.cmd.makeEntitySetColorCmd(entity, color)` (`line_react_util.tl:596`).
- Widgets: `line_react_util.ColorWidget{ entity = line }` and `line_react_util.NameTextView{ entity = line, locationButton = true, stackEntityOpen = true, editMode = true }` (`statistic_lines.tl:17-34`).

### 2.3 Carrier (road/tram/rail/water/air)
There is no single "carrier of line" field. The base has three approaches.

a) **Statistics filter** (by the transport modes of the stops, refined by the vehicle carriers). Use it as `line_util.filterLine({carrier}, line)`:
```lua
-- gui/gui/line_vehicle_mgmt/line_util.tl:2035-2095 (abridged)
local tm, c = api.type.enum.TransportMode, api.type.enum.Carrier
local transportModes = api.engine.util.line.getLineTransportModesUnion(lineEntity)
local hasRoadTm = transportModes[tm.BUS] or transportModes[tm.CAR] or transportModes[tm.TRUCK] or false
local hasRailTm = transportModes[tm.TRAIN] or transportModes[tm.ELECTRIC_TRAIN] or false
local hasTramTm = transportModes[tm.TRAM] or transportModes[tm.ELECTRIC_TRAM] or false
local hasAirTm  = transportModes[tm.AIRCRAFT] or transportModes[tm.SMALL_AIRCRAFT] or transportModes[tm.HELICOPTER] or false
local hasWaterTm = transportModes[tm.SHIP] or transportModes[tm.SMALL_SHIP] or false
-- + a road line that is fully tram-compatible counts as not road:
--   api.engine.util.line.isLineCompatibleWithAnyCarrier(line, {c.TRAM, c.RAIL}, false)
-- + line_util.getLineHasVehicles(line) checks tv.carrier of each vehicle
```
Usage: `if not line_util.filterLine(allowedCarriers, key) then return false end` (`statistic_lines.tl:317-321`). This is moderately expensive: it reads every vehicle's TRANSPORT_VEHICLE component and builds a transport-mode map per vehicle (`line_util.tl:1486-1560`).

b) **Carrier of the stop terminals** (used by the LVM):
```lua
local reactLine = line_util.getReactLineFromGameState(lineEntity)   -- line_util.tl:87-125
local carriers  = line_util.getLineCarriers(reactLine)              -- {Carrier = true}, line_util.tl:1306-1326
-- internally, per stop:
local carriers = api.engine.system.stationGroupSystem.getCarriers(stop.stationGroup, stationIndex0, terminalIndex0)[1]
```

c) **Vehicles' carrier** (cheapest when the line has vehicles):
```lua
for _, v in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(lineEntity)) do
  local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
  vehicleCarriers[tv.carrier] = true            -- line_util.tl:1851-1855
end
```
Carrier enum values: `api.type.enum.Carrier.ROAD|TRAM|RAIL|WATER|AIR` (`statistic_lines.tl:302-306`). Direct check: `api.engine.util.line.isLineCompatibleWithCarrier(line, carrier, distinguishTramFromRoad)` (`apidef/api/engine/util.d.tl:218-223`; used at `manager_window.tl:159`).

### 2.4 Vehicles and count
```lua
local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(entity)   -- {Engine.Entity}
local count = #vehicles
```
- `statistic_lines.tl:38-41`: `useStepState`, every step, once per row.
- For a dashboard covering all lines: `api.engine.system.transportVehicleSystem.getLine2VehicleMap()` returns `{line = {vehicle}}` (`system.d.tl:361`). It is NOT used by the base (needs in-game verification), but it saves one call per line.
- Widget: `vehicle_react_util.VehicleWidget({vehicleEntities = vehicles})`. Clicking it opens the LVM with `react.fireEvent(nil, "openVehicleManager", { openWithLineEntity = entity })` (`statistic_lines.tl:46-53`).

### 2.5 12-month balance (statistics "Balance", line window "Last Year")
```lua
-- line_react_util.LineBalance, gui/gui/line_vehicle_mgmt/line_react_util.tl:621-627
local gameTimeComponent = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
local toTime = gameTimeComponent.gameTime
local fromTime = math.max(toTime - api.util.getDefaultYearDuration(), 0)
return api.engine.util.finance.calculateBalance({lineEntity}, fromTime, toTime, true)
```
- This is a rolling 12-month window, not a calendar year. The line window labels it "Last Year" (`gui/gui/entity_window/line/line_eow.script.tl:305-311`); the LVM tooltip says "Annual profit or loss." (`manager_window.tl:4003-4008`).
- `calculateBalance(entities, startTime, endTime, maintenanceIncomeOnly, maintenanceType?) -> integer` (`apidef/api/engine/util.d.tl:841-848`). With `true`, only maintenance and income journal entries count.
- **Inconsistency in base:** the displayed cell passes `{lineEntity}`, but the statistics *sort* value passes the line's vehicles: `calculateBalance(getLineVehicles(line), fromTime, toTime, true)` (`statistic_lines.tl:289-294`). The two can differ, for example for vehicles that were moved between lines. To match what the player sees, use `{lineEntity}`.
- Cost: one native journal sum. `LineBalance{entity=, stepTimer=true}` polls every 0.5 s; with `stepTimer=false` it polls every step (`line_react_util.tl:628`). Ready widget: `line_react_util.LineBalance{ entity = line, stepTimer = true }` (red/green text, `formatMoney`).

**Last year vs this year:** the base shows no "this year vs last year" number. Two derived options:
```lua
-- (derived, not base) two rolling windows with the same API:
local Y = api.util.getDefaultYearDuration()
local now = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
local last12  = api.engine.util.finance.calculateBalance({line}, math.max(now - Y, 0), now, true)
local prev12  = api.engine.util.finance.calculateBalance({line}, math.max(now - 2*Y, 0), math.max(now - Y, 0), true)
```
- Per-year bars as in the line window's Balance chart: `api.engine.util.finance.getAccountChart(entity, config)` with `config = api.type.ChartConfig.new(); config.count = <years>` (`gui/gui/entity_window/entity_window_util.tl:868-883`). The line window uses `chartType = "account"` with labels `{_("Income"), _("Running Costs")}` (`line_eow.script.tl:658-675`).
- `ChartResult.series : {{{number}}}` (`apidef/api/type.d.tl:5624-5639`). The exact point layout (`{x, y}` per point, one series per label) needs in-game verification.
- Transported items over the last 12 months: `api.engine.util.logbook.getLogValuePerYear(line, "itemsTransported")` (`line_react_util.tl:642-645`).

### 2.6 Load / Capacity / Utilization / Satisfaction (statistics columns)
```lua
-- statistics_react_util.calculateCargoColumnDataForLine, gui/gui/statistics/statistics_react_util.tl:245-258
local locationParams = { lineEntity = lineEntity, getTendency = true, showEmpty = true }
local cargoTypes = cargo_util.getSortedProducedCargoTypes(locationParams, "CAPACITY")
local cargoTypeInfos = {}
for _, cargoTypeId in ipairs(cargoTypes) do
  cargoTypeInfos[#cargoTypeInfos + 1] = cargo_util.getCargoTypeInfo(cargoTypeId, locationParams)
end
return statistics_react_util.calculateCargoColumnData(cargoTypeInfos)
-- -> { supply = sum(count), demand = sum(capacity), coverage = supply/demand, averageQuality = mean }
```
- The column mapping (`statistic_lines.tl:408-411`) is "Load" = `supply`, "Capacity" = `demand`, "Utilization" = `coverage` (fraction 0..1, shown with `api.util.toStringPercentPrecision(v, 0)`, `statistic_lines.tl:148-172`), "Satisfaction" = `averageQuality` (0..1).
- LVM tooltips (`manager_window.tl:3945-3967`): Capacity = "Maximum load of all vehicles combined."; Utilization = "Percentage of the capacity that is currently used." It is a snapshot of current on-board load, not a time average.
- Native core underneath (`gui/gui/main/cargo_util.tl:707-722`):
  ```lua
  local capacities = api.engine.util.line.getLineCapacityUsages(lineEntity, false)  -- false = current load config
  local capacityUsage = capacities and capacities[cargoTypeId + 1] or nil           -- NOTE: 1-based array, index = cargoTypeId+1
  -- capacityUsage.used, capacityUsage.capacity (numbers)
  ```
  Cheap version for a dashboard (derived): sum `used` and `capacity` over `pairs(getLineCapacityUsages(line, false))`, then utilization = used/capacity. Unlike `calculateCargoColumnDataForLine`, this skips the quality lookups (`getCargoQualityDataForLine` per cargo type).
- **Surprise:** the type says `{CargoTypeId : LineCapacityUsage}` (`apidef/api/engine/util.d.tl:198`), but base code treats it as 1-based (`cargo_util.tl:710`, `cargo_util.tl:897-898`: `cargoTypeId = cargoTypeIndex - 1`).
- Cost: statistics recomputes `calculateCargoColumnDataForLine` 4 times per row (separate Load/Capacity/Utilization/Satisfaction cells, each with its own `useStepStateTimer` at 0.5 s), plus once more per sort compare.

### 2.7 Frequency (interval)
```lua
-- line_util.calculateFrequencySeconds, gui/gui/line_vehicle_mgmt/line_util.tl:1350-1354
local maxFrequency = api.engine.util.line.getMaxFrequency(entityId)
if maxFrequency < 0.0001 then return 0 end
return math.floor(1.0 / maxFrequency)
```
- Returns an integer interval in seconds; 0 means none.
- Display:
  - statistics: `api.util.formatMinutesSeconds(sec)` (`statistic_lines.tl:200-218`);
  - line window: `api.util.formatSeconds(sec)` for the label and `formatMinutesSeconds` for the tooltip, with `"--"` when 0 (`line_eow.script.tl:56-78`).
- The LVM tooltip says "Time interval between the vehicles." (`manager_window.tl:3971-3981`).

### 2.8 Rate (throughput)
```lua
local rate = api.engine.util.line.calcLineStationThroughput(lineEntity)   -- integer
```
- `statistic_lines.tl:220-230`, `line_eow.script.tl:34-54`.
- Unit: "Amount of cargo or passengers a line can transport per year" (`manager_window.tl:3989-3999`). Display it with `lang_util.formatInt(rate)`.

### 2.9 Stops (station group + name per stop)
```lua
-- gui/gui/line_vehicle_mgmt/line_manager_panel.tl:1371-1381 (abridged)
local line = api.engine.getComponent(lineEntity, api.type.ComponentType.LINE)
for i, stop in ipairs(line.stops) do               -- i is 1-based; engine stopIndex0 = i - 1
  local sg = stop.stationGroup                       -- station group entity
  local stopName = api.engine.util.getEntityName(sg) or _("Station")
  -- stop.station (0-based station index in group), stop.terminal (0-based), stop.waypoints, stop.stopConfig.load[cargoTypeId+1]
end
```
- LINE.Stop fields: `apidef/api/engine.d.tl:523-549`.
- Cargo types configured to load at a stop: `cargo_util.getConfiguredStopCargoTypes({ lineEntity = line, stopIndex1 = i }, true)` (`cargo_util.tl:819-839`; it reads `stop.stopConfig.load`, index-1 = cargoTypeId).

### 2.10 Waiting passengers and cargo per stop
Passengers, as in the station window's per-line stop rows:
```lua
-- gui/gui/entity_window/station_group/station_group.tl:703-705
local passengerCargoTypeId = cargo_util.getPassengerCargoTypeId()
local qualityData = api.engine.util.cargo.getCargoQualityDataAtStop(lineEntity, stopIndex0, passengerCargoTypeId)
-- qualityData.countTotal (waiting), .countBad (unhappy), .averageQuality (number|nil), .isVeryBad
```
- `CargoQualityData` is defined at `apidef/api/engine/util.d.tl:716-723`. It is userdata; call `:clone()` before you keep it in state (`cargo_react_util.tl:380`).
- Count only, without quality: `api.engine.system.simEntityAtTerminalSystem.getLineStopSimEntitiesCount(line, stopIndex0, cargoTypeId)` (`system.d.tl:186-199`). It exists in the API but the base never calls it.
- Waiting passengers grouped by destination stop: `getLineStopSimEntities(line, stopIndex0, passengerId)`, then `SIM_ENTITY_AT_TERMINAL.lineStop1` (`station_group.tl:648-690`). This is heavy: one component read per passenger.
- The stop index must be one the line has. Rows of a stops table refresh on a timer, so a row can outlive its
  stop by a refresh; read the stops from the `LINE` component in the same callback (`cards.lua` reads all stops
  in the table's timer and its cells only look them up).
- Cargo: the base shows no waiting-cargo count per stop anywhere. The station window counts passengers only.
  - In TF3, cargo is loaded from the stock lists of catchable industries and warehouses (`cargo_util.getInputOutputStocksForStation` → `catchmentAreaSystem.getStationCatchables(station, true)`, `cargo_util.tl:544-563`).
  - The `getCargoQualityDataAt*` docs say "cargo type (passengers allowed)", so calling `getCargoQualityDataAtStop(line, stopIndex0, cargoTypeId)` for each type from `getConfiguredStopCargoTypes` is the closest API. Whether it returns non-zero for cargo needs in-game verification.
  - Line-wide cargo on board: `cargo_util.calculateSortedLineCargoInfo(line)` returns `{ {cargoType, capacity, vehicleEntities, ...} }` (`cargo_util.tl:352-355`). **No `fill`:** the inner function counts it only with its third argument `calculateFill`, which neither `calculateSortedLineCargoInfo` nor `calculateSortedVehicleCargoInfo` passes (`cargo_util.tl:283-355`), so `fill` is nil and a load summed from it is always 0 (the mod's vehicle load read 0 until 2026-10). For one vehicle's load use `cargo_util.calculateSortedVehicleCargoInfoCompareValue(vehicle)`, the one export that passes it: `{ {cargoType, fill, capacity} }` (`cargo_util.tl:357-364`), or `api.engine.system.simEntityAtVehicleSystem.getVehicleSimEntitiesCountForCargoType(vehicle, cargoType)` per cargo type.

### 2.11 Problems / issues per line with reason text
**Engine sources** (the same ones the notification script uses, `game_mechanics/game_mechanics/notifications/notifications.script.tl:122-178`):
```lua
local misconfiguredLines = api.engine.util.line.getLinesIssues(api.engine.util.getPlayer(), false) -- {line = {LineIssue}}
local lineAndProblems    = api.engine.util.line.getLineProblems()  -- {{line, LineProblem int, PathProblemLocation?}}, all lines
local lineStationProbs   = api.engine.util.line.getLineStationProblems() -- {{line, stationGroup, LineStationProblem int}}
```
- Types (`apidef/api/type.d.tl`):
  - `LineProblem` (2138-2145) = `NOTHING, ZERO_OR_ONE_STATION, DOUBLE_STATIONS, INCOMPATIBLE_STATIONS, NO_PATH, BAD_ALTERNATIVE_TERMINAL`;
  - `LineStationProblem` (2148-2155) = `StopUseless, PassengerStopUseless, CargoStopUseless, AllPassengerStopUseless, CargoTypeUnloadUseless, CargoTypeLoadUseless`;
  - `LineIssue` (5716-5728) = `{ type : LineIssue.Type (NowhereToLoad|NowhereToUnload|NoVehicleToLoadCargo|VehicleUseless|LineCargoConfig|None), stopIndex, cargoType }`.
- Enum access:
  - `api.type.enum.LineProblem.NO_PATH`;
  - `api.type.LineIssue.Type.NowhereToLoad` (note: not under `enum`, `line_warning.script.tl:15`).
- Per-line detail: `api.engine.util.line.getLineIssues(line, false)`, and `getDetailedLineProblems(line) -> {{StopState}}` (segments → stops with `noPath`, `duplicateStop`, `incompatibleStop`, `noPathToAlternative`, `noPathFromAlternative`; `apidef/api/engine/util.d.tl:177-210`).
- `lineSystem.getProblemLines(player)` exists (`system.d.tl:44-46`) but is not used by the base.
- Cost:
  - The notification script splits the work: line problems run on tick % 4 == 0, line-station problems on tick % 4 == 1 (`notifications.script.tl:13,49,122,180`).
  - The LVM time-slices `getDetailedLineProblems` over 4 lines per step and rotates the system-wide calls (`getVehicleProblems`, `getVehiclesWithRoundTripCount`, `getLinesIssues`) round-robin, one per step (`gui/gui/line_vehicle_mgmt/manager_window.tl:5958-6066`). Copy that pattern for a dashboard.

**Human-readable text.** The base text lives in the local `getDescription` of the notification type. It is not exported, so you cannot call it. Either mirror the strings (exact base strings, `game_mechanics/game_mechanics/notifications/types/line_warning.script.tl:6-142`):

| Source | Short text (`iconExplainTooltip`) | Long text (`description`) |
|---|---|---|
| `LineIssue.Type.NowhereToLoad` | "Some Cargo Type Configurations of This Line Are Clashing" | "A cargo type cannot be loaded anywhere, despite being configured on the line.\nCargo Type: {cargoType}" |
| `NowhereToUnload` | (same) | "A cargo type cannot be unloaded anywhere, despite being loaded at stop {stopNumber}.\nCargo Type: {cargoType}" |
| `NoVehicleToLoadCargo` | (same) | "No vehicle on the line can transport some of the cargo configured to be loaded.\nCargo Type: {cargoType}" |
| `VehicleUseless` | (same) | cargoType >= 0: "Some vehicles on the line cannot transport any of the cargo configured to be loaded."; else "Some vehicles can only transport cargo, but the line is configured for passengers." |
| `LineCargoConfig` | (same) | "The line isn't configured to load any cargo." |
| `LineProblem.ZERO_OR_ONE_STATION` | "Line Contains Too Few Stations" | "Line {line} contains too few stations." |
| `DOUBLE_STATIONS` | "A Station Appears Consecutively Twice" | "On line {line} a station appears consecutively twice." |
| `INCOMPATIBLE_STATIONS` | "Stations Are Incompatible Due to Conflicting Stops" | "Stations are incompatible as there are conflicting stops on {line} connected." |
| `NO_PATH` | "Could Not Connect Stations" | "Could not connect stations on {line}: {reason}." |
| `BAD_ALTERNATIVE_TERMINAL` | "Could Not Connect Alternative Terminals" | "Could not connect all alternative terminals on {line}: {reason}." |

- `{cargoType}` = `api.res.cargoTypeRep.get(cargoTypeId).name`. `{stopNumber}` = `stopIndex + 1`.
- `{reason}` = `line_util.getRelaxationText(line_util.getRelaxationType(okModes, relaxedModes, allowedModes))`. It is exported, `line_util.tl:1966-2031`, and returns "Missing catenaries" / "Missing tram lane" / "Missing tram tracks" / "Missing train tracks" / "Missing road". `okModes`, `relaxedModes` and `allowedModes` come from `lineAndProblem[3]` (`PathProblemLocation`, `apidef/api/engine/util.d.tl:150-166`).
- Station-stop texts are in `game_mechanics/game_mechanics/notifications/types/line_station_warning.script.tl:5-100`. Example: `StopUseless` → "Stop Not Compatible With Current Vehicles" / "Stop of {line} at {station} cannot be used with current vehicles."
- Wrap mirrored strings in `_()` so the base translations apply.

…or read the active persistent notifications for the line and render their own `title`/`description`. This is what the statistics Problems column and the LVM do:
```lua
-- statistic_lines.tl:384 (once per table refresh)
local entity2ids = notification_util.getPersistingEntity2NotificationFromNative(
                     notification_util.externalGetNotificationsStateNative())        -- {entity = {notificationId}}
-- line_react_util.tl:108-125 (ManagerNotificationWidget): keep Problem/Caution only
local native = notification_util.externalGetNotificationsStateNative()
for _, id in orderedPairs(entity2ids[lineEntity] or {}) do
  local n = notification_util.getNotificationFromNative(native, id)       -- {type, params, simParams}
  local guiType = n and notification_util.getGuiTypeFromNotificationType(n.type)
  if guiType == "Problem" or guiType == "Caution" then list[id] = n end
end
-- line_react_util.tl:63-65, in a CHILD recipe per notification (useDataState contains hooks!):
local dataStateFn = util.useFn(n.type .. "@useDataState")
local dataState = dataStateFn and dataStateFn(n.params, n.simParams) or nil
-- dataState.title ("Line Problem"), .iconExplainTooltip (short), .description (long), .onClick(stack)
```
- Module paths:
  - `notification_util` = `game_mechanics/game_mechanics/notifications/notification_util.tl` (functions at lines 12, 280, 294, 376);
  - `util` = `scripts/scripts/util.tl`.
- **Hook rule:** `useDataState` calls `useStepStateTimer` internally (`line_warning.script.tl:181`). Call it only inside a dedicated child recipe with `meta = { localKey = tostring(id) }`, as `WarningIcon` (`statistics_react_util.tl:317-344`) and `ManagerNotificationWidgetEntry` do. Never call it in a variable-length loop inside one recipe.
- **Same hooks on every render:** the hooks of one recipe instance are kept by position, so a recipe declares the same ones in the same order on every render, also after an error. A render that can fail does not choose between its own hooks and the base recipe in one recipe: `gui/fallback.lua` puts the hooks in a child recipe and has a parent with fixed hooks show the base after a failure. A callback of `useStepState`/`useStepStateTimer` runs inside the hook on the first render (`useStateLazy`, `engine_react_util.tl:74`, `:139`), so it must not raise either.
- `line_station_warning` notifications persist on both the line and the station group (`entities = {line, stationGroup}`, `notifications.script.tl:187-192`), so they appear under the line too.
- Problem notifications are created even when their type is ignored, which is the default for line, station and overcrowding, `initiallyIgnoredType = true` in `types/line_warning.res.lua:8`. They are only marked `dismissed=true, tracked=false`. They are dropped only when `ignored.fully` is set (`game_mechanics/game_mechanics/notifications/notification_util.tl:137-146`). So reading persisting notifications works in free play.
- Ready-made cell: `statistics_react_util.ProblemsCell` (DataTable cell; needs `userParam.notificationState = entity2ids`, `statistics_react_util.tl:346-367`).

---

## 3. Vehicles

Paths are relative to `.game/game/`. Short forms used below: `LVM/` = `gui/gui/line_vehicle_mgmt/`, `EOW/` = `gui/gui/entity_window/`.

**Units used in this section**
- `GAME_TIME.gameTime` and `TransportVehiclePart.purchaseTime` are integer game ticks, which are game milliseconds. The stuck check proves this: it compares a difference of `gameTime` against `1000 * 60 * 5` (`game_mechanics/game_mechanics/notifications/notifications.script.tl:560`).
- Durations in calendar terms:
  - `api.util.getDefaultYearDuration()`, `getDefaultMonthDuration()`, `getDefaultDayDuration()` give ticks at default calendar speed (`apidef/api/util.d.tl:110-120`).
  - `api.util.getYearDuration(millisPerDay)` gives ticks at the current calendar speed (`util.d.tl:105-108`).
  - `millisPerDay` comes from the `GAME_SPEED` component (`apidef/api/engine.d.tl:415-422`). It is 0 when paused, so guard against it as `finances_loan_gui.tl:55-58` does.
- Money values are plain integers in game currency. Format them with `api.util.formatMoney(int)`.

### 3.0 Component and enum reference (verified)

`api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)` returns `Engine.Component.TransportVehicle` (`apidef/api/engine.d.tl:1380-1530`). Fields relevant to a dashboard:

| field | meaning |
|---|---|
| `carrier` | `api.type.enum.Carrier.ROAD/TRAM/RAIL/WATER/AIR` |
| `transportVehicleConfig.vehicles[i]` | `TransportVehiclePart{ part{modelId, reversed, color, …}, purchaseTime, maintenanceState, maintenanceChange, autoLoadConfig }` (`apidef/api/type.d.tl:1511-1524`) |
| `state` | `TransportVehicleState` (see below) |
| `userStopped` | the player stopped the vehicle |
| `depot` | depot entity if the vehicle is in a depot or heading to one |
| `sellOnArrival` | the vehicle will be sold at the depot |
| `line`, `stopIndex` | assigned line; next stop index (0-based) |
| `noPath` | the vehicle has no path |
| `daysInDepot`, `daysAtTerminal` | integer days |
| `maintenanceStation` | -1 if the vehicle is not maintained |
| `loadState`, `timeUntilDeparture`, `lastLineStopDeparture`, `sectionTimes`, `lineStopDepartures` | scheduling data |

`TransportVehicleState` (`apidef/api/type.d.tl:438-447`) has only 4 values: `IN_DEPOT`, `EN_ROUTE`, `AT_TERMINAL`, `GOING_TO_DEPOT`. Read them as `api.type.enum.TransportVehicleState.X`. "Stopped by the player" is not a state; it is the separate flag `userStopped`.

Base polling hooks (`gui/gui/main/engine_react_util.tl`):
- `useStepState(fn)` re-evaluates every frame.
- `useStepStateTimer(fn, interval=0.5)` re-evaluates every 0.5 s by default (`engine_react_util.tl:126-157`).

Both run on the GUI thread. The base computes no vehicle data with `useStepStateParallel`.

### 3.1 Line (and "In Depot" / "Going to Depot")
Base treats `tv.line` as valid only while the state is `EN_ROUTE` or `AT_TERMINAL` (`EOW/vehicle/vehicle.tl:157`, `EOW/vehicle/vehicle_eow.script.tl:901-909`, `gui/gui/statistics/statistic_vehicles.tl:280-286`):
```lua
-- statistic_vehicles.tl:280-286
local getLineCompareValue = function(vehicleEntity)
  local tv = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
  if tv.state == api.type.enum.TransportVehicleState.EN_ROUTE or tv.state == api.type.enum.TransportVehicleState.AT_TERMINAL then
    return api.engine.util.getEntityName(tv.line)
  end
  return (tv.state == api.type["enum"].TransportVehicleState.GOING_TO_DEPOT) and _("Going to Depot") or _("In Depot")
end
```
Next stop as a station group plus "Stop i of n" (`EOW/vehicle/vehicle_eow.script.tl:40-58`):
```lua
local tv = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
if tv.state == api.type["enum"].TransportVehicleState.EN_ROUTE or tv.state == api.type["enum"].TransportVehicleState.AT_TERMINAL then
  local line = api.engine.getComponent(tv.line, api.type.ComponentType.LINE)
  local stopIndex = tv.stopIndex
  if stopIndex >= 0 and stopIndex < #line.stops then
    entity = line.stops[stopIndex + 1].stationGroup     -- stopIndex is 0-based
  end
  numStops = #line.stops
else
  entity = tv.depot
end
```
For bulk lookups: `api.engine.system.transportVehicleSystem.getLine2VehicleMap()` returns `{line : {vehicle}}`, and `getLineVehicles(line)` returns the vehicles of one line (`apidef/api/engine/system.d.tl:349-400`).

### 3.2 Age, lifespan, age in years and % of lifespan
```lua
-- LVM/vehicle_util.tl:31-34
vehicle_util.getLifespan = function(modelId)
  local maintenance = api.res.modelRep.get(modelId).metadata.maintenance
  return maintenance.lifespan * 1000              -- metadata value * 1000 = game ticks (ms)
end
-- LVM/vehicle_util.tl:36-52  getMinPurchaseTimeAndLifespan(tv) -> { minPurchaseTime, lifespanOfThatPart }
--   (oldest part wins; ties go to the shorter lifespan)
-- LVM/vehicle_util.tl:297-314
vehicle_util.getAge = function(vehicleEntity)
  local transportVehicle = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
  local purchaseTimeAndLifetime = vehicle_util.getMinPurchaseTimeAndLifespan(transportVehicle)
  local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
  local currentGameTime = gt.gameTime
  local ageString = api.engine.util.formatAge(purchaseTimeAndLifetime[1], currentGameTime)
  local timeRemaining = nil
  if currentGameTime < purchaseTimeAndLifetime[1] + purchaseTimeAndLifetime[2] then
    timeRemaining = api.engine.util.formatAge(currentGameTime, purchaseTimeAndLifetime[1] + purchaseTimeAndLifetime[2])
  end
  return {
    age = ageString,                                        -- e.g. "6 years" (formatAge uses the current calendar speed)
    purchaseTime = purchaseTimeAndLifetime[1],              -- ticks
    agePercent = math.max(0, mathutil.round((currentGameTime - purchaseTimeAndLifetime[1]) / purchaseTimeAndLifetime[2] * 100)), -- 0..100+, already *100
    timeRemaining = timeRemaining                           -- string or nil once the lifespan is reached
  }
end
```
- Usage: `local vehicle_util = require "::/gui/line_vehicle_mgmt/vehicle_util.tl"` and `vehicle_util.getAge(v)`. The statistics "Age" column polls this with `useStepStateTimer` (`statistic_vehicles.tl:234-252`) and sorts by `getAge(v).purchaseTime` (`:312-314`).
- `api.engine.util.formatAge(t0, t1) -> string` is defined at `apidef/api/engine/util.d.tl:1066-1070`.
- **Numeric years:** no base helper exists. Use the same conversion the base uses for durations (`scripts/scripts/util.tl:40-49`):
  ```lua
  local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED)
  local years = gs.millisPerDay > 0 and (now - purchaseTime) / api.util.getYearDuration(gs.millisPerDay) or nil
  ```
- **Pitfall:** `agePercent` is already ×100. `api.util.toStringPercent*` expects a fraction (`apidef/api/util.d.tl:13-22`), so pass `agePercent / 100`.
- **Base bug:** the line window's vehicle table computes `agePerc = math.floor(age / lifespan)` and formats it with `toStringPercentPrecision`. Because of the floor, the tooltip shows "0 % of Lifetime" until the lifespan is reached (`EOW/line/line_eow.script.tl:138-145`).

### 3.3 Condition / maintenance state
```lua
-- LVM/vehicle_util.tl:285-295   -> (avgState 0..1, avgChange); 1.0 if the vehicle has no parts
vehicle_util.getAvgMaintenanceState = function(vehicleEntity)
  local transportVehicle = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
  local change, stateSum = 0.0, 0.0
  for _, vehiclePart in ipairs(transportVehicle.transportVehicleConfig.vehicles) do
    stateSum = stateSum + vehiclePart.maintenanceState
    change = change + vehiclePart.maintenanceChange
  end
  local num = #transportVehicle.transportVehicleConfig.vehicles
  return (num > 0 and stateSum / num or 1.0), (num > 0 and change / num or 0.0)
end
-- LVM/vehicle_util.tl:159-184  5 levels: index = clamp(ceil(condition*5), 1, 5)
-- "Very Bad","Bad","Mediocre","Good","Very Good"   (pGetText("vehicle-condition", ...))
vehicle_util.getConditionText(condition)   -- localized string
vehicle_util.getConditionIcon(condition)   -- "::/gui/line_vehicle_mgmt/icons/condition_*.tga"
```
- The statistics "Condition" column uses `useStepStateTimer` and shows `getConditionText(getAvgMaintenanceState(v))` (`statistic_vehicles.tl:215-232`).
- The vehicle window shows `RatingBar{ value = state, valueChange = change, numFractions = 5 }` with the tooltip `toStringPercentPrecision(state, 0)` (`EOW/vehicle/vehicle_eow.script.tl:1084-1124`).
- Engine alternative: `api.engine.util.vehicle.getVehicleMaintenanceState(v) -> number` (`apidef/api/engine/util.d.tl:518-520`). The "vehicle condition" notification fires when this is `<= 0.2` and clears above `0.3` (`notifications.script.tl:306-318`).
- Penalties in percent: `api.engine.util.vehicle.getMaintenanceEmissionPenalty`, `...ComfortPenalty`, `...RunningCostPenalty`, `...TopSpeedPenalty` (`engine/util.d.tl:490-505`).

### 3.4 State text: moving / at terminal / in depot / stopped / no path
This is the base "status" line under the vehicle renderer (`EOW/entity_window_util.tl:2310-2350`):
```lua
local tv = api.engine.getComponent(entityId, api.type.ComponentType.TRANSPORT_VEHICLE)
if tv.userStopped then
  message = speed > 0 and _("Stopping") or _("Stopped")
elseif tv.state == api.type["enum"].TransportVehicleState.EN_ROUTE
    or tv.state == api.type["enum"].TransportVehicleState.GOING_TO_DEPOT then
  if tv.noPath then
    message = _("No Path")                                  -- shown with a warning style
  elseif api.engine.system.landVehicleMoveSystem.isTrainWaitingForFreePath(entityId) then
    message = _("Waiting for Free Path")
  else
    message = api.util.formatSpeed(speed)                   -- speed = api.engine.util.vehicle.getSpeed(entityId)
  end
elseif tv.state == api.type["enum"].TransportVehicleState.AT_TERMINAL then
  -- loading/unloading messages (makeVehicleLoadingMessages)
end
-- IN_DEPOT / GOING_TO_DEPOT labels: _("In Depot") / _("Going to Depot")  (vehicle_eow.script.tl:934)
```

### 3.5 No-path and stuck detection (three sources)
1. Per-vehicle flag: `tv.noPath` (above).
2. Engine list:
   - `api.engine.system.transportVehicleSystem.getNoPathVehicles() -> {entity}` (`engine/system.d.tl:372-373`). No base GUI call site was found.
   - `api.engine.util.vehicle.getVehicleProblems() -> {{ {entities}, VehicleProblem }}` (`engine/util.d.tl:484-486`). `VehicleProblem` is one of `NoPathElectric | NoPathShip | NoPathAircraft | NoPathGeneric | Blocked` (`apidef/api/type.d.tl:2158-2164`). One problem can name several vehicles; `Blocked` lists two trains.
   - Human-readable text for these problems: `game_mechanics/game_mechanics/notifications/types/vehicle_warning.script.tl:5-62`. Examples: short `_("No Electrified Path")`, `_("No Path at All")`, `_("Trains Are Blocking Each Other")`; long `lang_util.format(_("There is no path at all for {vehicle}."), {vehicle = name})`.
   - Cost: this scans the whole system. The LVM calls it only every 3rd step, round-robin with `getVehiclesWithRoundTripCount` and `getLinesIssues` (`LVM/manager_window.tl:6048-6060`). The notifications game script calls it once per `NumNotificationsTypeSplit` ticks (`notifications.script.tl:49, 260-273`).
3. "Stuck" (base definition) (`notifications.script.tl:545-570`):
   ```lua
   if tv.state == api.type["enum"].TransportVehicleState.EN_ROUTE and not tv.userStopped then
     if api.engine.util.vehicle.getSpeed(vehicleEntity) == 0 then addProblem(vehicleEntity) end   -- remembers problemSince = gameTime
   end
   -- reported once: gameTime - problemSince >= 1000*60*5   (5 game minutes, ms)
   ```
   This runs only in the notifications game script. A GUI mod needs its own "since" map, or it can read the persistent `stuck_vehicle` notifications (see §5).

### 3.6 12-month balance (exactly as statistics)
```lua
-- LVM/vehicle_react_util.tl:414-434 (recipe VehicleBalance); identical sort value in statistic_vehicles.tl:290-295
local gameTimeComponent = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
local toTime = gameTimeComponent.gameTime
local fromTime = math.max(toTime - api.util.getDefaultYearDuration(), 0)
local balance = api.engine.util.finance.calculateBalance({vehicleEntity}, fromTime, toTime, true)  -- integer money
-- display: api.util.formatMoney(balance), css class "negative"/"positive"
```
- Signature: `calculateBalance(entities, startTime, endTime, maintenanceIncomeOnly, maintenanceType?) -> integer` (`apidef/api/engine/util.d.tl:840-848`).
- `maintenanceIncomeOnly = true` counts only income and running costs, without purchase or sale. This is a rolling window of the last default year, although the vehicle window labels it "Last Year" (`vehicle_eow.script.tl:753-773`).
- The statistics cell uses `VehicleBalance{entity = v, stepTimer = true}` (0.5 s timer, `statistic_vehicles.tl:254-268`). Without `stepTimer` it re-evaluates every frame.
- Cost: a native journal query per call. The statistics table runs one timer per visible cell, and sorting calls it for every vehicle.
- Per-year chart data: `entity_window_util.EntityDiagramWidget{ chartType = "account", ... }` (`vehicle_eow.script.tl:786-850, 1195-1225`).

### 3.7 Model name, vehicle name, icons
```lua
-- LVM/vehicle_react_util.tl:15-37  (first part's model)
local tv = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
local part = tv.transportVehicleConfig.vehicles[1]
local desc = api.res.modelRep.get(part.part.modelId).metadata.description
local modelName = desc.name           -- localized model name; icons: desc.icon20, desc.icon20cblend
local vehicleName = api.engine.util.getEntityName(vehicleEntity)   -- the vehicle name shown in the UI (engine/util.d.tl:1038-1040)
```
- For a whole train, list all parts: `vehicle_util.GetVehicleModelIds(v) -> {modelId}` (`LVM/vehicle_util.tl:316-324`).
- `VehicleInfoType` builds the name as "A (3x)\n + B" (`EOW/vehicle/vehicle_eow.script.tl:86-140`).
- Purchase price of a model: `api.res.modelRep.get(modelId).metadata.cost.price` (`LVM/vehicle_store_window.tl:4038-4040`).

### 3.8 Depreciated value, running cost
```lua
api.engine.util.vehicle.getDepreciatedValue(vehicleEntity)  -- integer money; the refund the vehicle store credits on sell/replace (LVM/vehicle_store_window.tl:3525-3527, 3538-3541)
api.engine.util.vehicle.getRunningCost(vehicleEntity)       -- number, per year (EOW/entity_window_util.tl:162 rounds it)
api.engine.util.vehicle.getPartPrice(transportVehiclePart)  -- integer
```
These are defined at `apidef/api/engine/util.d.tl:462-472`.
- The player's vehicles: `api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE, { requireOwnedByPlayer = api.engine.util.getPlayer() })`. The engine applies the filter (`EntityFilters`, `apidef/api/engine.d.tl:1693-1713`; used by `G/statistics/statistic_vehicles.tl:322` and `LVM/manager_window.tl:1359`), so no `PLAYER_OWNED` read per vehicle is needed. `filterFn` in the same record is a Lua callback per entity ("very slow").

---

## 4. Stations (station groups)

### 4.1 Which station groups
```lua
-- gui/gui/statistics/statistic_stations.tl:262-269 (statistics only lists groups that have lines)
api.engine.forEachEntityWithComponent(function(entity)
  local lines = api.engine.system.lineSystem.getLinesForStationGroup(entity)
  if entity_util.isOwnedByPlayerOrNotOwned(entity) then
    if #lines > 0 then stationGroups[#stationGroups + 1] = entity end
  end
end, api.type.ComponentType.STATION_GROUP)
```
- This runs every step while the stations tab is open (`useStepState(makeTableState)`). `entity_util` = `scripts/scripts/entity_util.tl`.
- STATION_GROUP component = `{ stations = {stationEntity} }` (`apidef/api/engine.d.tl:1121-1126`). Name: `api.engine.util.getEntityName(sg)`.
- Station group of a station: `api.engine.system.stationGroupSystem.getStationGroup(station)`.

### 4.2 Lines served
```lua
local lines = api.engine.system.lineSystem.getLinesForStationGroup(entity)   -- {line}
```
- `statistic_stations.tl:59-66` (count, `useStepStateTimer`).
- With stop indices: `lineSystem.getLineStops(sg) -> {{line, stopIndex0}}`. Per terminal: `getLineStopsForTerminal(station, terminalIndex0)` (`station_group.tl:695`). Map for all groups: `getStationGroup2LineStopsMap()` (`system.d.tl:46-48`).
- The station window shows only player-owned lines (`entity_util.isOwnedByPlayer(lineEntity)`, `station_group.tl:699-700`).

### 4.3 Waiting count per cargo
Passengers (statistics, HUD, station window):
```lua
local q = api.engine.util.cargo.getCargoQualityDataAtStationGroup(sg, cargo_util.getPassengerCargoTypeId())
-- q.countTotal waiting, q.countBad unhappy ("Delay" column), q.isVeryBad
```
- Sources: `statistic_stations.tl:154-156`, `gui/gui/main/hud_icon_toolbox.tl:234-238`.
- Per terminal: `getCargoQualityDataAtTerminal(sg, stationTerminal, passengerId)` (`hud_icon_toolbox.tl:219`). Per station: `getCargoQualityDataAtStation(station, cargoTypeId)`. Per line stop: §2.10.
- Cargo types: the base never queries per-cargo waiting counts at stations. The API accepts any `cargoTypeId` ("passengers allowed", `apidef/api/engine/util.d.tl:743-764`), so loop `api.res.cargoTypeRep.getAll()` ids (as `cargo_util.getCargoTypesCount`, `cargo_util.tl:6-14`). Whether cargo yields counts needs in-game verification: TF3 cargo is loaded from catchment stock lists (§4.5), not stored at the station.

### 4.4 Capacity / overcrowding
```lua
-- statistic_stations.tl:113-120  ("Utilization" column)
local usage = api.engine.util.station.calculateStationGroupCargo(stationGroupEntity, -1)
if usage.capacity == 0 then -- ports and heliports do not have people waiting on the terminals, so look at stops via qualityData instead
  local qualityData = api.engine.util.cargo.getCargoQualityDataAtStationGroup(stationGroupEntity, cargo_util.getPassengerCargoTypeId())
  usage.used = qualityData.countTotal
end
-- displayed as "{used}/{capacity}" with capacity = usage.capacity + usage.waitingHallCapacity  (statistic_stations.tl:131-140)
```
- `StationGroupCapacityUsage = { capacity, waitingHallCapacity, used : integer, overflow : boolean }` (`apidef/api/engine/util.d.tl:541-552`). The second argument is a flat terminal index, or -1 for the whole group.
- Overcrowding = `calculateStationGroupCargo(sg, -1).overflow`. This is exactly what the "Station Overcrowded" notification uses (`notifications.script.tl:589`; type `types/overcrowding.res.lua`: `guiType = "Caution"`, `initiallyIgnoredType = true`).
- Per terminal and waiting hall, as in the station window (`station_group.tl:641-646, 757-797`). This is passenger stations only:
  ```lua
  if api.engine.util.station.isStationOfType(stationId, false) then          -- false = passenger
    local pool = api.engine.util.station.calculateStationTerminalUsage(stationId, -1)    -- waiting hall {used, capacity}
    local term = api.engine.util.station.calculateStationTerminalUsage(stationId, i - 1) -- terminal i
    local overflowing = term.used > term.capacity and (pool.used > pool.capacity or station.pool.capacity == 0)
  end
  ```
- Station-level: `api.engine.util.station.calculateStationUsage(station) -> {totalUsed, overflow, poolCapacity, terminalCapacity}` (`util.d.tl:526-532`). The base uses it only in `game_mechanics/game_mechanics/emission/emissions.script.tl:213`.
- Station type: `statistics_react_util.getStationGroupType(sg)` returns `"Passenger"|"Cargo"|"Mixed"|nil` via `isStationOfType` (`statistics_react_util.tl:13-41`).
- Upkeep: `api.engine.util.maintenance.calcMaintenanceForStationGroup(sg)` returns an integer money value, shown with `formatMoney` (`statistic_stations.tl:189-205`).
- Problems on a station: read the persisting notifications of the group and of each station entity, as the station window does (`station_group.tl:859-862`). Types are `overcrowding`, `station_useless` and `line_station_warning`.
- Cost:
  - Statistics uses `useStepStateTimer` (0.5 s) per cell.
  - The station window rebuilds the full terminal/stop state every step (`useStepState(makeTerminalsAndStopsState)`, `station_group.tl:819`), including per-passenger destination tooltips. Avoid copying that wholesale.

### 4.5 Catchment (towns / industries), cheap variants
```lua
-- town of a station group (statistic_stations.tl:30-41)
local stationGroup = api.engine.getComponent(entity, api.type.ComponentType.STATION_GROUP)
if #stationGroup.stations == 0 then return -1 end
local town = api.engine.system.stationSystem.getTown(stationGroup.stations[1])
for _, station in ipairs(stationGroup.stations) do
  if api.engine.system.stationSystem.getTown(station) ~= town then return -1 end   -- -1 = mixed/none
end
return town
```
- All at once: `api.engine.system.stationSystem.getStation2TownMap()` (`system.d.tl:61`; used by the auto-rename town scheme, `gui/gui/line_vehicle_mgmt/auto_rename/scheme_components/scheme_component_town.script.tl:3`).
- Industries and warehouses: `api.engine.system.catchmentAreaSystem.getStationCatchables(stationEntity, true)` returns `{entity}` holding a StockList (`false` = PersonCapacity entities; `system.d.tl:445-448`). Base uses:
  - `cargo_util.getInputOutputStocksForStation(station)` → `inputCargoTypes, inputCount, outputCargoTypes, outputCount` (`cargo_util.tl:544-563`);
  - `station_useless` detection (`notifications.script.tl:601`).
- Mapping a catchable stock-list entity back to its industry (for a name) is NOT FOUND in base code. `cargo_util.getStockListEntityFromOwner` only goes owner → stockList (`cargo_util.tl:565-581`). The reverse needs in-game verification, e.g. `getEntityName(stockList)` or `streetConnectorSystem.getConstructionEntityForSubconstruction`.
- Cost: getStationCatchables is a cached system lookup. Per-stock reads (`calculateStockConfigs`) are heavier, so poll them at 1 s or more.

---

## 5. Notifications

Abbreviations: `NM` = `game_mechanics/game_mechanics/notifications/`, `T` = `NM/types/`, `G` = `gui/gui/`.
Module paths for `require`: `"::/game_mechanics/notifications/notification_util.tl"`,
`"::/game_mechanics/notifications/types/notification_react_util.tl"`.

### 5.1 Data model (where the state lives)

- One game script owns all notifications: `NM/notifications.gs.lua` → `notifications.script@update` / `@handleEvent`.
  Its state is `NotificationsState` (`NM/notifications.d.tl:79-127`):
  `notifications : {id → Entry}`, `history : {id}` (oldest first), `ignored = {fully, types}`, `paused`.
- `Entry` (`notifications.d.tl:80-88`): `timestamp` (game ms), `notification`, `persisting : {EntityAndRevision}`
  (non-empty = persistent/active), `dismissed`, `expired`, `tracked`, `playedInitialSound`.
- `Notification` (`notifications.d.tl:52-58`): `type` (= script module path of the type, e.g.
  `"::/game_mechanics/notifications/types/line_warning.script"`), `params`, `notificationId`, `autoDismissDuration`
  (game ms; `notification_util.defaultAutoDismissDurationMs = 60000`, `notification_util.tl:10`), `simParams`.
- Persistent entries are recomputed by the game script in 4 round-robin slices
  (`currentTick % 4`, `notifications.script.tl:13,49`) and diffed by `updatePersistentNotifications`
  (`notification_util.tl:205-258`). The diff compares `params` with `deepEquals`, so a change of parameters
  (for example a subsidy's `status` going from offered to active, `notifications.script.tl:462-489`) ends the old
  entry (`dismissed = expired = true`) and adds a new one with a new id, timestamp and `playedInitialSound = false`.
  The base ridge therefore plays Resolve and the initial sound, and shows the new icon at the end.
- Thread: the state belongs to the game-script (engine) side. The GUI reads it read-only through the
  GameScript component (`notification_util.externalGetNotificationsStateNative`, `notification_util.tl:280-285`).
  It changes it only by sending script events (§5.4-5.6).

### 5.2 Reading active (persistent) notifications per entity, with title text

**A) Inside an EOW plugin (you get `params.gameCtx`)**: use the game-wide cache.

```lua
-- created ONCE per game UI: G/main/game.tl:127, exposed as gameCtx.accessNotificationCacheFn (game.tl:178,
-- type G/main/game_context.d.tl:64:  accessNotificationCacheFn : function(Engine.Entity) : {Notification})
local notifications = params.gameCtx.accessNotificationCacheFn(entity)   -- {Notification}, each with .notificationId
```
Implementation (`T/notification_react_util.tl:89-114`): it re-reads the native state and rebuilds
`entity → {id}` on every step (`react.onStep`). The lookup itself is cheap. The `.d.tl` comment says
"use as little as possible for whole game (once, if possible)" (`notification_react_util.d.tl:28`), so do not
call `createNotificationCacheAccessFn()` yourself per widget.
Base consumer: `NotificationHudIcons` polls it with `useStepStateTimer` (`notification_react_util.tl:146-166`).

**B) Anywhere (ModEntryPoint, game bar, own windows: no gameCtx)**: the base pattern from the statistics tables
(`G/statistics/statistic_lines.tl:381-386`) and `entity_window_util.NotificationWidget` (`G/entity_window/entity_window_util.tl:2129-2160`):

```lua
local notification_util = require "::/game_mechanics/notifications/notification_util.tl"

-- entity -> {notificationId} for ALL persisting notifications (statistic_lines.tl:384)
local makeState = function()
  local native = notification_util.externalGetNotificationsStateNative()            -- NativeLuaTable
  local byEntity = notification_util.getPersistingEntity2NotificationFromNative(native) -- {entity : {id}}
  local result = {}
  for entity, ids in pairs(byEntity) do
    for _, id in ipairs(ids) do
      local n = notification_util.getNotificationFromNative(native, id)   -- plain table copy (asTable)
      n.notificationId = id
      local guiType = notification_util.getGuiTypeFromNotificationType(n.type) -- "Problem"|"Caution"|"Info"|...
      result[#result + 1] = { entity = entity, notification = n, guiType = guiType }
    end
  end
  return result
end
local state = engine_react_util.useStepStateTimer(makeState, 1.0)
```
- `getPersistingEntity2NotificationFromNative` (`notification_util.tl:294-322`) maps every entity in
  `persisting`. Multi-entity notifications appear under each entity. For example `line_station_warning`
  persists `{line, stationGroup}` (`notifications.script.tl:189-192`).
- Filters used by base: statistics "Problems" column = only `guiType == "Problem"` (`G/statistics/statistics_react_util.tl:261-285`);
  LVM icons = `"Problem"` or `"Caution"` (`G/line_vehicle_mgmt/line_react_util.tl:107-125`); EOW widget = all.
- The persistent set ignores `dismissed`/`tracked`. Problems that are hidden by default (`initiallyIgnoredType`)
  are still listed here. Only `ignored.fully` (missions) suppresses entries.
- Cost: `getPersistingEntity2NotificationFromNative` walks the whole history (≤100 non-persistent + all
  persistent entries) through native-table `find()` calls. Base runs it every step in several places
  (`useStepState` in `NotificationWidget`/`ManagerNotificationWidget`, the table state in the statistics). For a
  dashboard, one `useStepStateTimer(…, 0.5-1 s)` per window is enough. Nothing in base runs it in parallel.

**Title / description text.** The text comes from the type's GUI module `type .. "@useDataState"`.
`useDataState` is a hook: it calls `useStepStateTimer` internally, see `T/stuck_vehicle.script.tl:39` and the
`.d.tl` warning in `NM/notifications.d.tl:46-49` ("only use in recipe WITHOUT another DEPENDENT state … use as last
state … use localKey in parent"). So you must render one child recipe per notification, keyed by id.
The base pattern is from `G/statistics/statistics_react_util.tl:317-343` (WarningIcon) and `entity_window_util.tl:2060-2127`:

```lua
local util = require "::/scripts/util.tl"

local MyNotificationRow = react.RegisterRecipe("UioNotificationRow", function(params)
  local dataStateFn = util.useFn(params.notification.type .. "@useDataState")
  local dataState = dataStateFn and dataStateFn(params.notification.params, params.notification.simParams) or nil
  if dataState == nil then
    return builtin.BoxLayout{}                         -- useDataState returns nil while the entity is gone/changed
  end
  return builtin.BoxLayout{ children = {
    builtin.Button{
      content = builtin.TextView{ text = dataState.title .. ": " .. dataState.description },
      onClick = dataState.onClick and function() dataState.onClick(true) end or nil,  -- true = stack window
    },
  }}
end)
-- parent:  MyNotificationRow{ meta = { localKey = tostring(id) }, notification = n }
```
`NotificationGuiData` fields (`NM/notifications.d.tl:5-39`): `title`, `description`, `icon`, `hudIcon`
(persistent only, icon above the entity), `lvmIcon` (shown in LVM), `iconExplainTooltip`, `previewImage`,
`soundOnMount`, `wouldClick()`, `onClick(stack, dryRun?)`, `status` ("Pending"|"Failed"), `progress`/`progresses`.
- Base titles are generic per type, for example `"Line Problem"` (`T/line_warning.script.tl:208`). The
  human-readable reason is in `description`, which is built from `LineProblem`/`LineIssue` in
  `T/line_warning.script.tl:6-160`.
- **Hook-free alternative:** the static per-type label from the resource:
  `notification_util.getNotificationType2Label()` → `{typeName : label}` (`notification_util.tl:44-57`). It
  walks `genericRep`, so cache the result (e.g. `react.useRefLazy`).
- Ready-made widgets: `entity_window_util.NotificationWidget(entity)` (all persisting notifications as cards, `entity_window_util.tl:2129`)
  and `line_react_util.ManagerNotificationWidget(entity)` (Problem/Caution icons, `line_react_util.tl:107`). See §8.

### 5.3 Defining a notification type (`notification` generic resource)

A type is a pair of files with the same base path. The resource name `X.res` maps to the type string `X.script`
by `gsub(".res$", ".script")` (`notification_util.tl:38,52,95`). The GUI module is loaded through
`util.useFn(type .. "@useDataState")`.

```lua
-- T/stuck_vehicle.res.lua (complete)
function data()
  return {
    type = "notification",
    data = {
      guiType = "Caution",                 -- "Info"|"Caution"|"Problem"|"Opportunity"|"Achievement" (notifications.d.tl:6-13)
      label = _("Vehicle Stuck"),          -- shown in the log's filter tree (getNotificationType2Label)
      initiallyIgnoredType = true,         -- put into ignored.types when a NEW game starts (notification_legacy_util.tl:10-19)
      -- simUpdateScript = "<path>.sim.script@updateData",  -- optional, see below
    },
  }
end
```
All `data` fields read by code: `guiType` (`notification_util.tl:22,76,92`), `label` (`:49`),
`initiallyIgnoredType` (`:36`), `simUpdateScript` (`:65`). Nothing else is read.
An official mod uses the minimum, `data = { guiType = "Info" }`
(`urbangames_campaign_mission_05::/mission/tasks/drilling/mission_drilling_notification.res.lua`).

- `simUpdateScript` → `updateData(params, oldSimParams) → simParams` runs in the game script at add time
  (`notification_util.tl:149-156`) and then every 30 ticks per id (`notifications.script.tl:14,72-80`). Base uses
  it to cache names for when an entity has gone (e.g. `T/vehiclecondition.sim.script.tl:6-28`). The result is
  passed as the 2nd arg to `useDataState`.
- `initiallyIgnoredType` is applied only by `makeInitialState()` (new game, and the legacy reset at
  `notification_legacy_util.tl:453`). **A mod type added to an existing save is not ignored**
  (`ignored.types[type]` is nil → `tracked = true`, `notification_util.tl:145-146`).
- The GUI module `X.script` returns `{ useDataState = function(params, simParams) … end }` and runs in the GUI react
  state. Reference: `T/stuck_vehicle.script.tl:1-61`.

### 5.4 Ignored-types set at runtime (`updateIgnoredTypes`)

The handler is in `NM/notifications.script.tl:741-764`:
- It replaces `ignored` with `{types = param.ignoredTypes or {}, fully = true}`.
- It adds every type of each `param.ignoredGuiTypes` entry.
- It then sets `fully = param.ignoreFully` if that is given.
- The state is only written if `param ~= nil`.

Base GUI sender (the notification log's filter tree, `NM/gui/notification_log.tl:468-472`):
```lua
local cmd = api.cmd.makeScriptingSendEventCmd("", "Notifications", "updateIgnoredTypes", {
  ignoredTypes = newIgnoredTypeSet,     -- {["::/game_mechanics/notifications/types/line_warning.script"] = true, ...}
  ignoreFully = false,
})
commit(newLogState, cmd)               -- engine_react_util.useStepState commit (sends the command)
```
Missions send `ignoreFully = true` (`mission_x/mission/mission_sim.script.tl:789-792`).

Mod recipe: "un-hide line problems" (read-modify-write, the same as the log; read the current set exactly like
`notification_log.tl:336`):
```lua
local native = notification_util.externalGetNotificationsStateNative()
local ignored = native:find("ignored"):asTable()             -- {fully=bool, types={name=true}}
if not ignored.fully then                                      -- base log refuses when fully (notification_log.tl:458)
  local types = {}
  for k, v in pairs(ignored.types or {}) do types[k] = v end
  types["::/game_mechanics/notifications/types/line_warning.script"] = nil
  api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", "updateIgnoredTypes",
    { ignoredTypes = types, ignoreFully = false }))           -- ALWAYS pass ignoreFully=false, default is true!
end
```
Caveat: `dismissed`/`tracked` are fixed when an entry is created (`notification_util.tl:145-146`). Changing the set
does not re-show entries that already exist. They show only after they expire and come back.
Other events of this script: `enlist {id}` (show in popups), `dismiss {id}`, `pause bool`, `initialSound {notificationId}`
(`notifications.script.tl:733-786`).

### 5.5 Adding new persistent notifications from a mod (`updatePersistent`)

Handler (`NM/notifications.script.tl:719-725`): `param` is a `PersistentNotifications` (`NM/notifications.d.tl:60-68`):
```lua
{
  type = "<modId>::/path/my_type.script",           -- type string = res path with .res -> .script
  entitiesAndParam = {                               -- the COMPLETE current set for this type
    { entities = { entity_util.makeEntityAndRevision0(e) },  -- {EntityAndRevision}; drives HUD/EOW/LVM/stat lookup
      param = { ... } },                             -- your params (plain data, no userdata)
  },
  passOnlyParam = true,  -- true: notification.params = param;  false/nil: params = {entities=..., param=...}
}
```
- Diff semantics (`notification_util.tl:205-258`): for this `type`, every existing persistent entry whose
  `entities`+params are not in the new list is ended (`persisting=nil, dismissed=true, expired=true`). New
  ones are added. So send the whole set each time, and an empty `entitiesAndParam = {}` clears all of them.
  Base never touches foreign types (`getPersistentHistoryByType` groups by type, `notification_util.tl:341-374`).
- To end a single one: `removePersistent { type, entities }` (`notifications.script.tl:726-732`, `notification_util.tl:260-278`).
- With `passOnlyParam=false`, entries also auto-expire when all `params.entities` changed revision
  (`notifications.script.tl:94-107`). With `passOnlyParam=true` that check finds no `params.entities`.
- `add` (one-shot) is ignored while `paused` (missions, `:712-715`). `updatePersistent` has no paused check.

**Who may send it.** Any code that can call `api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", name, param))`
(`apidef/api/cmd.d.tl:788`). The event is routed by `id == "Notifications"` to the notification game script,
which subscribes to `"updatePersistent"` (`notifications.script.tl:22-31`). Verified senders:
- Game script (engine thread): official mod `urbangames_campaign_mission_05::/mission/tasks/drilling/drilling.tl:45-53`
  (sends `updatePersistent` with `passOnlyParam = true`) and `:17-23` (`removePersistent`). Base game scripts send `add` the same way
  (`game_mechanics/game_mechanics/company/company.script.tl:111-118`). In `update()` such commands are executed
  immediately (comment `company.script.tl:96`). Do not pass a callback there.
- GUI (react state): the base GUI sends events of the same script with the same command
  (`notification_log.tl:468`, `notification_popups.tl:107,287`). So a GUI-only mod can send `updatePersistent` from a
  recipe (e.g. a ModEntryPoint `react.onStepTimer`). Only send when your set changed (compare with `table_util.deepEquals`),
  because every command mutates and saves the state.
- `game.interface.*` / `sendScriptEvent`: NOT FOUND anywhere in TF3 sources or apidef. Use `makeScriptingSendEventCmd`.
- Console one-liner from base: `api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", "add", { title = "A Notification" }))`
  (`notifications.script.tl:11`).

### 5.6 Complete minimal example: "Unprofitable line" (modelled on `stuck_vehicle`)

Modelled on `T/stuck_vehicle.res.lua` + `T/stuck_vehicle.script.tl` (single-entity, `passOnlyParam = true`,
sender block `notifications.script.tl:535-573`). The type string format follows the official mod
(`urbangames_campaign_mission_05::/mission/tasks/drilling/mission_drilling_notification.script`).

```lua
-- content/uio/notifications/unprofitable_line.res.lua
function data()
  return {
    type = "notification",
    data = {
      guiType = "Caution",
      label = _("Line Unprofitable"),
      initiallyIgnoredType = false,
    },
  }
end
```
```lua
-- content/uio/notifications/unprofitable_line.script.lua   (GUI side; returns a table)
local entity_util       = require "::/scripts/entity_util.tl"
local lang_util         = require "::/scripts/lang_util.tl"
local engine_react_util = require "::/gui/main/engine_react_util.tl"
local notification_util = require "::/game_mechanics/notifications/notification_util.tl"

local data = {}
data.useDataState = function(p)              -- p = { entity = EntityAndRevision }  (keep volatile numbers OUT of params)
  local icon = "::game_mechanics/notifications/gui/icons/stuck_vehicle.tga"   -- base icon path (stuck_vehicle.script.tl:14)
  local state = engine_react_util.useStepStateTimer(function()
    if entity_util.entityChanged0(p.entity) then return nil end
    local now = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
    local balance = api.engine.util.finance.calculateBalance({ p.entity.entity },
      math.max(now - api.util.getDefaultYearDuration(), 0), now, true)
    return { name = api.engine.util.getEntityName(p.entity.entity), balance = balance }
  end, 2.0)
  if not state:old() then return nil end
  return {
    title = _("Line Unprofitable"),
    description = lang_util.format(_("{name} lost {money} in the last 12 months."),
      { name = state:old().name, money = api.util.formatMoney(-state:old().balance) }),
    icon = icon,
    hudIcon = nil,                            -- line has no single map position; leave nil
    lvmIcon = icon,                           -- shows in LVM line list (line_react_util.tl:66)
    iconExplainTooltip = _("Line Is Losing Money"),
    wouldClick = notification_util.makeDefaultWouldClick({ p.entity }),
    onClick = notification_util.makeDefaultOnClick({ p.entity }),   -- focusEntity + selectEntity (notification_util.tl:436-471)
  }
end
return data
```
```lua
-- sender (GUI, e.g. inside a ::ModEntryPointExtension plugin recipe; or the same body in a *.gs.lua update)
local entity_util = require "::/scripts/entity_util.tl"
local table_util  = require "::/scripts/table_util.tl"
local TYPE = "uio_1::/uio/notifications/unprofitable_line.script"   -- "<modId>::/<path under content/>.script"

local lastSent = react.useRef(nil)
react.onStepTimer(function()
  local now = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
  local from = math.max(now - api.util.getDefaultYearDuration(), 0)
  local list = {}
  for _, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
    local balance = api.engine.util.finance.calculateBalance({ line }, from, now, true)   -- as LineBalance (line_react_util.tl:621-627)
    if balance < 0 then
      local er = entity_util.makeEntityAndRevision0(line)
      list[#list + 1] = { entities = { er }, param = { entity = er } }   -- stable params: no balance here
    end
  end
  if not table_util.deepEquals(list, lastSent:get()) then
    lastSent:set(list)
    api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", "updatePersistent", {
      type = TYPE, entitiesAndParam = list, passOnlyParam = true,
    }))
  end
end, 10)   -- seconds
```
Notes:
- Params are compared with deepEquals (`notification_util.tl:229-230`): any change in `param` ends the old entry and
  creates a *new* one (new popup/log line). That is why the example keeps the balance out of `param` and computes it
  in `useDataState`. `makeEntityAndRevision0` stores only `revision.num[1]` (`scripts/scripts/entity_util.tl:11-17`),
  so edits to the line that bump that number also re-create the entry.
- **Needs in-game verification:** the exact `getName()` form of a mod's res (the type string must equal it for
  the ignore set and the log filter tree), and whether `_()` works in a mod `.res.lua`.

---

## 6. Actions

General rules:
- Commands: `api.cmd.sendCommand(cmd, function(cmdData, success, resultEntities) end)` (`apidef/api/cmd.d.tl:590-600`). Callbacks fire on the GUI side (examples in `EOW/vehicle/vehicle.tl:338-350`).
- React events: fire them with `react.fireEvent(nil, name, param)` inside recipes, or with `api.gui.fireReactEvent(name, param)` outside React (`apidef/api/gui.d.tl:46-49`).
- All handlers named below live in entry points that the base mounts permanently in `GameUIRoot` (`gui/gui/main/game.tl:270-285`), so the events work while the windows are closed.
- **Respect mission locks** as the base does:
  - `gameCtx.filters:get().protectedEntities[entity]` (truthy means protected; type `{entity : ProtectionConfig|boolean}`, `gui/gui/main/game_context.d.tl:38-58`);
  - `game_react_globals.getDisableFeatures()[feature]`, where the features are `CreateNewLine`, `GameSpeedControl`, `GameSpeedPause`, `HudIconMaster`, `Layers`, `OpenEntityWindow`, `PerkHudIcons` (`gui/gui/main/disable_features.d.tl:3-11`).
  - Only EOW plugins receive `gameCtx`. `GameUIRoot` fills `protectedEntities` from the `setProtectedEntities` event (`game.tl:156-159`), which the mission script fires whenever the set changes (`mission_x/mission/mission_sim.script.tl:1239-1242`). Code without a gameCtx can keep its own copy from the same event in a `ModEntryPointExtension` plugin, which mounts with `GameUIRoot` (`game.tl:578-586`); the mod's `actions.lua` does that for the `uio.action` event. The base events (`duplicateVehicles`) check the mission lock themselves; a send to depot does not, so check `protectedEntities` before you sell on arrival.

### 6.1 Clone a vehicle into its line: event `duplicateVehicles`
Handler: `LVM/manager_window.tl:8494-8561`, mounted in `ManagerEntryPoint`. Param type `DuplicateVehiclesParam` (`LVM/manager_window.d.tl:131-140`):
```lua
-- base call from the vehicle window, EOW/vehicle/vehicle.tl:428-437
react.fireEvent(nil, "duplicateVehicles", {
  vehicleEntities = { vehicleEntityId },
  addFeedback = addFeedback,                 -- function(message, mode, dialogData, id); REQUIRED (called on failure)
  onBuy = function(resultEntities) end,      -- REQUIRED for line assignment, see below
})
```
What the handler does, per vehicle:
1. It copies the config: `api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)`, then sets `purchaseTime = 0` and `maintenanceState = 1` on every part.
2. It asks mission scripts for permission with `api.gui.fireGuiScriptEvent("vehicleStore", "mission.buyVehicle", {modelId2quantity, actuallyBuy = true})`. If an error string comes back, it calls `addFeedback(err)` and stops. It also fires `"mission.cloneVehicle"`.
3. It queues a `VehicleChange{ vehicleEntity = -v - 1, config = newConfig }`. A negative id means "buy new"; the original id is encoded in it.
4. It calls `vehicle_react_util.HandleVehicleChanges(toAdd, protectedEntities, getLineAndDepot, getFirstStopToSendTo, param.onBuy, onFail)` with:
   - `getLineAndDepot = function(v) return api.engine.util.vehicle.findBestLineAndDepotForVehicle(-v - 1) end`, which returns `{line, depot}` (`engine/util.d.tl:425-428`);
   - `getFirstStopToSendTo`, which uses the player's "first stop to send" scheme (`manager_window.tl:8531-8549`).

`HandleVehicleChanges` (`LVM/vehicle_react_util.tl:319-412`) is the buy, assign, replace and sell chain:
```lua
-- for each change: parts with purchaseTime <= 0 get the current gameTime; autoLoadConfig = all true
if change.vehicleEntity < 0 then
  local lineEntity, depotEntity = table.unpack(getLineAndDepot(change.vehicleEntity))
  if depotEntity >= 0 then
    api.cmd.sendCommand(api.cmd.makeVehicleBuyCmd(api.engine.util.getPlayer(), depotEntity, change.config),
      function(command, success)
        if not success then if onFail then onFail(_("Could not clone vehicles (not enough money).")) end return end
        if onBuy then                                             -- <<< line assignment only happens if onBuy ~= nil
          if lineEntity >= 0 then
            local stop = getFirstStopToSendTo and getFirstStopToSendTo(command.resultVehicleEntity, lineEntity) or 0
            api.cmd.sendCommand(api.cmd.makeVehicleSetLineCmd(command.resultVehicleEntity, lineEntity, stop))
          end
          onBuy({{ command.resultVehicleEntity, entity_util.makeEntityAndRevision(command.resultVehicleEntity).revision }})
        end
      end)
  elseif onFail then onFail(_("Could not find suitable depot.")) end
elseif #change.config.vehicles == 0 then                          -- empty config = sell
  if protectedEntities == nil or not protectedEntities[change.vehicleEntity] then
    api.cmd.sendCommand(api.cmd.makeVehicleSellCmd({change.vehicleEntity}))
  end
else                                                              -- replace
  api.gui.spawnEphemeralHudImage("::/gui/main/icons/symbol_emote_happy_colored.tga", change.vehicleEntity) -- if hudFilter.showEventIcons
  api.cmd.sendCommand(api.cmd.makeVehicleReplaceCmd(change.vehicleEntity, change.config))
end
```
- **Surprise:** pass a non-nil `onBuy`; otherwise the clone stays in the depot. The vehicle window passes an empty function for this reason.
- `addFeedback` is how the player learns why nothing was bought (mission error, "Could not clone vehicles (not enough money).", "Could not find suitable depot."). The vehicle window renders `feedback_list_util.FeedbackList(react.ref(ref), {})` under its action buttons and forwards to `ref:get():getApi().addFeedback(message, mode, dialogData, nil, id, true)` while `not ref:hasExpired()` (`EOW/vehicle/vehicle.tl:302-311, 627`). The stylesheet for it applies inside any entity window (`R::EntityWindowContent R::FeedbackList`, `entity_window.css.lua:147-157`). A function that only logs leaves the click without any visible result.
- `vehicle_react_util.onBuy` does NOT EXIST. `onBuy` is a callback parameter, and `vehicle_react_util.getLineAndDepot` does not exist either.
- `makeVehicleBuyCmd(player, depot, tvc) -> VehicleBuyCommandData{ resultVehicleEntity }` (`cmd.d.tl:892, 425-433`) and `makeVehicleSetLineCmd(vehicle, line, stopIndex0)` (`cmd.d.tl:922`).

### 6.2 Send to depot (optionally sell on arrival)
```lua
-- EOW/vehicle/vehicle.tl:338-350 (vehicle window) and LVM/manager_window.tl:5299-5307 (LVM bulk)
api.cmd.sendCommand(api.cmd.makeVehicleSendToDepotCmd(vehicleEntity, false), function(_, success)
  if not success then addFeedback(_("Vehicle could not be sent to depot."), nil, nil, nil) end
end)
```
- Signature: `makeVehicleSendToDepotCmd(vehicle, sellOnArrival, jumpToDepotEntity?)` (`apidef/api/cmd.d.tl:910-915`). The command goes to the nearest reachable depot, and the optional third argument teleports the vehicle there.
- The base never passes `sellOnArrival = true`: there are no call sites. Read the flag back via `tv.sellOnArrival`.
- Selling on arrival can crash the game itself. In the savegame World#1, train 108611 (the only vehicle on its line) sent with `sellOnArrival = true` crashes the simulation thread as it is sold in the depot: "Assertion `it != components.end()' failed ... Entity: 108611, Notified Entity: 108611, Component Type Index: 72" (TransportVehicle), "ecs::Engine::GetComponentDataIndex". This happens with no mod but the testbench (`make test-ingame WITHOUT="... ui_overhaul_1"`, build 40408, 2026-10-07). In-game checks that sell a vehicle must not run long after it reaches the depot.
- The base enables the button only while `state ~= IN_DEPOT and state ~= GOING_TO_DEPOT` (`vehicle.tl:352-355`).
- `line_util.sendVehiclesToDepot`, `sendVehiclesToLine` and `sellVehicle` are not module functions. They are fields of the LVM-internal `commonParams` record, declared in `line_util.d.tl:551-561` and implemented in `manager_window.tl:7208-7264`, and are unusable from a mod.

### 6.3 Sell
```lua
-- EOW/vehicle/vehicle.tl:357-362, 525-536
if params.gameCtx.filters:get().protectedEntities[vehicleEntityId] then
  addFeedback(_("Vehicle cannot be sold at this time."), nil, nil, nil)
else
  api.cmd.sendCommand(api.cmd.makeVehicleSellCmd({vehicleEntityId}))   -- takes a list (cmd.d.tl:904-908)
end
```
The LVM bulk sell asks for confirmation first, using `addFeedback(text, "Question", {onAccept = ..., acceptText, soundOnAccept = "SellVehicle"}, 2)`. It skips entities whose revision changed (`entity_util.entityChanged0`) (`LVM/manager_window.tl:5323-5350`). The refund is `getDepreciatedValue(v)` (§3.8).

### 6.4 Replace with another model
- UI path: `react.fireEvent(nil, "replaceVehicles", VehicleStoreEventParam{ vehicleEntities, carrier, transportModes, filterTags, openedFromEOW, onClose })`. Base call: `EOW/vehicle/vehicle.tl:440-468`, which takes `carrier` and `transportModes` from `line_util.getLineAndVehicleCompatibleTransportModesAndCarrier({v})` and `filterTags` from `vehicle_store_util.getVehicleFilterTags({v})`. The handler is at `LVM/vehicle_store_window.tl:4895-4930` and opens the store in "Replace" mode.
- **How the base builds the new config.** The base does not auto-pick a model; the player chooses in the store. Buy-immediately carriers (no cart) take a single part (`vehicle_store_window.tl:4042-4060`):
  ```lua
  local part = vehicle_util.makePart(modelId, true, color)      -- LVM/vehicle_util.tl:8-29: modelId, reversed=not forward, one LoadConfig(0) per compartment, optional color
  local config = api.type.TransportVehicleConfig.new()
  config.vehicles = { part }
  config.vehicleGroups = { 1 }      -- not a multiple unit
  config.muFileNames = { }
  for _, entityToReplace in ipairs(toReplace) do result[#result+1] = { vehicleEntity = entityToReplace, config = config } end
  param.onAccepted(result)          -- -> HandleVehicleChanges -> makeVehicleReplaceCmd(v, config)
  ```
  The cart path concatenates `vehiclePartsLists` into `vehicles`, with `vehicleGroups = {#parts per list}` and `muFileNames = {muFileName per list}` (`vehicle_store_window.tl:4181-4203`).
  Multiple units expand through `api.res.multipleUnitRep.get(id).vehicles`, calling `makePart(api.res.modelRep.find(v.name), v.forward, color)` for each entry (`:4107-4113`).
- `purchaseTime` stays 0 in `makePart`. `HandleVehicleChanges` sets it to "now" (`vehicle_react_util.tl:333-341`).
- The vehicle keeps its entity id: `VehicleReplaceCommandData` has no result entity (`cmd.d.tl:436-444`). Nothing in the GUI is told about the new model; the base VehicleWidget re-reads `transportVehicleConfig` on a `useStepStateTimer` (`LVM/vehicle_react_util.tl:118-166`). Anything cached by vehicle id must re-read the config the same way (`lvm_models.lua` does every 2 s and before each action). Unverified: whether the Line Manager keeps the replaced vehicle in its list (it drops entries whose `revision.num[1]` grew, `entity_util.entityChanged0`); the in-game check `lvm_models_after_replace` logs the list size.
- Direct: `api.cmd.sendCommand(api.cmd.makeVehicleReplaceCmd(vehicleEntity, tvc))` (`cmd.d.tl:893-898`). The store also fires `api.gui.fireGuiScriptEvent("vehicleStore", "mission.buyVehicle", {...})` before buying (`:4226-4232`); mods that bypass it skip mission checks.

### 6.5 Open the Line/Vehicle Manager: event `openVehicleManager`
```lua
-- EOW/line/line.tl:144-147, statistics/statistic_lines.tl:48-51
react.fireEvent(nil, "openVehicleManager", { openWithLineEntity = lineEntity })
-- other fields (ManagerWindowEventParam, LVM/manager_window.d.tl:143-148):
--   openWithVehicleEntities = {v...}, sendToLineMode = true   -- "Send to Line" (EOW/vehicle/vehicle.tl:398-404)
--   openWithDepotEntity = depot                             -- (statistic_depots.tl:35, view_manager.tl:563)
```
The handler (`LVM/manager_window.tl:8447-8490`) resets the selection, closes the vehicle store, and pushes `ManagerTool` on the tool stack, which closes other tool windows such as Statistics or Finances. Close it with the `closeVehicleManager` event (`:8491`).

### 6.6 Open an entity window (stacked): event `selectEntity`
```lua
react.fireEvent(nil, "selectEntity", { entity = e, stack = true })   -- statistic_vehicles.tl:40
-- optional: dontBlink = true
```
The handler (`EOW/view_manager.tl:617-626`) calls `openWindow(entity, nil, not stack, dontBlink)`. With `stack = false`, all other entity windows close (`doCloseAll`). The event is ignored while `disableFeatures.OpenEntityWindow` is set. For non-entity windows there is `selectViewKey {entity?, nonEntity, stack, dontBlink, extraParam}` (`:627-635`).

### 6.7 Focus the camera on an entity
```lua
api.gui.camera.focusEntity(entity)              -- gui.d.tl:444-446; used by notification "goto" (notification_util.tl:450-454)
api.gui.camera.followEntity(entity, true)       -- jump + follow; used by the base "Locate" button (LVM/line_react_util.tl:220-224)
api.gui.camera.focusPosition(vec3, 15)          -- gui.d.tl:451; base distance 15 (line_react_util.tl:224)
```
The notification pattern is to focus and then open the window (`game_mechanics/game_mechanics/notifications/notification_util.tl:440-455`):
```lua
api.gui.camera.focusEntity(focusEntity)
api.gui.fireReactEvent("selectEntity", { entity = focusEntity, stack = stack })
```
`api.gui.*` is GUI thread only.

### 6.8 Open Statistics on a tab
```lua
react.fireEvent(nil, "openStatisticsWindow", "Line")   -- game_bar/game_bar.tl:99, 1102
```
- `TabKey` is one of `"Line" | "Vehicle" | "Station" | "Town" | "Industry" | "Warehouse" | "Depot"` (`gui/gui/statistics/statistics.d.tl:3-12`).
- The handler pushes `StatisticsTool` (`statistics/statistics.tl:691-693`). Close it with `closeStatisticsWindow`.

### 6.9 Open Finances
```lua
react.fireEvent(nil, "openFinanceWindow")              -- default tab "Overview" (game_bar/game_bar.tl:111, 322)
react.fireEvent(nil, "openFinanceWindow", "Loans")
```
- `FinanceToolParam.TabKey` is one of `"Overview" | "Finances" | "Assets" | "Loans" | "CargoLifetime"` (`game_mechanics/game_mechanics/finance/account.d.tl:3-10`).
- The handler is at `gui/gui/main/game.tl:290-301`. Close it with `closeFinanceWindow` (`:303`).

### 6.10 Set game speed
- The base game bar uses speedups `{0, 1, 2, 4}` (`game_bar/game_bar_widgets.tl:203, 239`). 0 is pause.
- It calls `GameSpeedApi.setSpeed` from `GameSpeedHelper`, a local recipe (`gui/gui/main/game.tl:617-712`). The helper is not reachable from mods: it is only passed into `game_bar.GameBar` as `gameSpeedHelper` (`game.tl:426`).
- The core command:
  ```lua
  -- game.tl:654-676
  if disableFeatures:old()["GameSpeedPause"] == true and speedup == 0 then return end
  local maxSpeedup = api.gui.game.getEstimatedMaximumGameSpeed()       -- GUI thread only; 0 = unknown (gui.d.tl:783-786)
  local clamped = maxSpeedup > 0 and math.min(speedup, maxSpeedup) or speedup
  api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(clamped))            -- cmd.d.tl:704-708
  ```
- Current speed: `api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED).speedup` (0 = paused).
- A direct command is safe: the helper re-syncs from `GAME_SPEED` each step (`game.tl:640-652`).
- Also respect `getDisableFeatures().GameSpeedControl` (`game.tl:693-695`).
- Calendar speed is separate: `api.cmd.makeGameSetCalendarSpeedCmd(millisPerDay)` (`cmd.d.tl:696-698`, used at `game_bar_widgets.tl:344`).

### 6.11 Save the game under the current save name (quicksave)
```lua
-- gui/gui/main/game.tl:790-795  (IA_QUICKSAVE handler, in the in-game React root)
local name = api.gui.game.getDefaultSavegameId()        -- string, current default save name (gui.d.tl:792-794)
app.saveGame(name, function() log.verbose("Save successful: " .. name) end, isMapEditorRef:get(), true)
-- isMapEditorRef holds api.gui.game.isMapEditor() (game.tl:731); a mod can call api.gui.game.isMapEditor() directly
```
- Signature: `app.saveGame(name, callBack, isMapEditor, skipSetName?)` (`apidef/app.d.tl:84-88`).
- The global `app` is declared in `apidef/api.d.tl:16` and is accessible in the in-game React state: `game.tl` itself calls it.
- `isMapEditor` comes from `api.gui.game.isMapEditor()` (`game.tl:731`).
- The pause-menu "Save Game" button opens the save page, which calls `app.saveGame(name, cb, isMapEditor, false)` (`gui/gui/menu/save_game_page.tl:189-204`). With `skipSetName = false`, that save becomes the new default name. The pause menu shows the name via `getDefaultSavegameId()` (`main/pause_menu.tl:394`).

---

## 7. Formatting helpers

All of `api.util.*` "can be called from anywhere" (`apidef/api/util.d.tl:3-4`), except those marked "Only available in GUI thread"
(`getApplicationTime`, `getInputMode`, ...).

| Function | Input → output | Base usage |
|---|---|---|
| `api.util.formatMoney(money)` | integer currency units or `nil` (= infinite) → localized string with currency (`util.d.tl:55-58`) | earnings plugin `:34`, finance table `finances_table.tl:311` |
| `api.util.formatMoneyNumber(money)` | number without currency (`util.d.tl:65-68`) | game bar `game_bar.tl:245` (prefix from `api.util.getAppConfig().moneyPrefix`, `:293`) |
| `api.util.formatMoneyAlt(money)` | opposite short/full format (`util.d.tl:60-63`) | game bar tooltip `game_bar.tl:243` |
| `api.util.formatKMB(n)` | number with K/M/B suffix (`util.d.tl:158-161`) | — |
| `api.util.toStringPercent(x)` | fraction 0..1 → "50%" (`util.d.tl:13-16`) | `construction_react_util.tl:2909` |
| `api.util.toStringPercentPrecision(x, decimals)` | (`util.d.tl:18-22`) | `construction_react_util.tl:301`, `:3858` |
| `lang_util.formatPercentageBoost(x)` | signed "+5%"/"-5%" (`scripts/scripts/lang_util.tl:16-25`) | construction descs |
| `lang_util.formatInt(i)`, `lang_util.formatNumber(v, decimals)` | localized numbers (`lang_util.tl:8-10`) | chart y-axis `entity_window_util.tl:1051` |
| `lang_util.format(str, {key = val})` | `{key}` interpolation (`string_util.format` = `stringutil.interp`, `lang_util.tl:7`) | everywhere |
| `api.util.formatDate(date, api.type.enum.DateFormat.X)` | `Date` → string; formats `LONG, SHORT, MEDIUM, FULL, FILENAME, YEAR` (`util.d.tl:143-147`, `type.d.tl:387-395`) | game bar `game_bar_widgets.tl:315` (MEDIUM), chart axis (YEAR) `entity_window_util.tl:1044` |
| `util.formatTimePoint(gameTime)` | game time → LONG date, or real-time string when paused-calendar (`scripts/scripts/util.tl:31-38`) | |
| `util.formatDurationWithCurrentCalenderSpeed(ms, millisPerDay, "OnlyMonth"|"Month"|"Year"|nil)` | duration (default-speed ms) → "2 Years 3 Months" (`scripts/scripts/util.tl:40-…`) | loan cards `finances_loan_gui.tl:271` |
| `api.util.formatSeconds(s)`, `formatMinutesSeconds(s, hideZero?)`, `formatDays(d)` | `util.d.tl:122-136` | line frequency `line_eow.script.tl:65`, `statistic_lines.tl:214` |
| `api.util.formatGameTime(gameTime)` | game time as real-time string (`util.d.tl:138-141`) | `util.tl:33` |
| `api.util.formatSpeed(m/s)`, `formatLength(m, dec?, small?)`, `formatWeight(t)`, `formatPower(kW)` | unit-system aware | |
| `api.engine.util.chart.getChartLabel(config, x, false)` | x-axis label for account/logbook charts (`entity_window_util.tl:1040,1047`) | |

`util` = `require "::/scripts/util.tl"`, `lang_util` = `require "::/scripts/lang_util.tl"` (base imports `ug_require "/scripts/..."`).

Base snippets:
```lua
-- money with sign colour (earnings plugin :19,:33-34)
builtin.TextView{ meta = { class = "font-scale-headline, " .. (v >= 0 and "positive" or "negative") }, text = api.util.formatMoney(v) }
-- calendar date (game_bar_widgets.tl:259-260, :269, :315)
local date = api.engine.util.getCalendarDate(gameTime.gameTime)
local apiDate = api.type.Date.new(date.year, date.month, date.day)
local text = api.util.formatDate(apiDate, api.type["enum"].DateFormat.MEDIUM)
-- plural (finances_charts.tl:175)
lang_util.format(nGetText("{count} Year", "{count} Years", n), { count = lang_util.formatInt(n) })
-- line frequency (line_eow.script.tl:65)
exact and api.util.formatMinutesSeconds(frequency) or api.util.formatSeconds(frequency)
```

**Translation** (`base/base/mod.lua:158-184`): `_(id)` = `pGetText(nil, id)`; `pGetText(context, id)` (e.g.
`pGetText("financial", "Assets")`, `account.tl:88`); `nGetText(singular, plural, n)`; `npGetText(context, singular, plural, n)`.
These are globals (`base/base/init.lua:29-38`). In GUI code they translate immediately when `_getTextNow` is set; in
`data()` resource files `pGetText` returns the (context-prefixed) id for later translation (`mod.lua:163-167`). Passing a table
to `_` logs a warning and returns it unchanged. A mod's own strings come from its `strings.lua` (per tf3-modding skill; not in base GUI source).

---

## 8. Reusable base GUI widgets

**Root rule.** Every recipe must return a *layout* builtin as root (`BoxLayout`, `FloatingLayout`, …) and put
plain components (`TextView`, `Button`, `Component`, `DataTable`) inside it.
- This is not enforced in Lua. `react.lua:262-295` only checks *wrapper* recipes (0 or 1 child of the wrapped
  builtin). The C++ framework enforces it: a non-layout root logs `Recipe child must be a layout` →
  `ReactFramework::Load() failed`, and the **whole game UI** drops. This is verified in-game
  ([CONTRIBUTING.md, "Rules the game enforces"](../CONTRIBUTING.md#rules-the-game-enforces), tf3-modding `references/engine.md:152-155`).
- Base follows it everywhere: even `LinesStatistic` returns `builtin.FloatingLayout` (`G/statistics/statistic_lines.tl:436`).
  Window wrapper recipes return `builtin.Window` (`RegisterWrapperRecipe`).
- `builtin.Component{ layout = BoxLayout{…} }` is how a component gets children (`scripts/scripts/builtin.d.tl:760-766`).

Requires (plain Lua mod): `local line_react_util = require "::/gui/line_vehicle_mgmt/line_react_util.tl"`, likewise
`vehicle_react_util.tl`, `G/entity_window/entity_window_util.tl` (`"::/gui/entity_window/entity_window_util.tl"`),
`"::/gui/main/gui_react_util.tl"`, `"::/gui/statistics/statistics_react_util.tl"`, `builtin = require "::/gui/main/builtin.lua"`.

### 8.1 `line_react_util.LineBalance{ entity, stepTimer }`
- Signature: `LineBalance : Recipe<{entity : Engine.Entity, stepTimer : boolean}>` (`G/line_vehicle_mgmt/line_react_util.d.tl:65-69`).
- What it shows: `api.util.formatMoney(calculateBalance({line}, now - 1 year, now, true))` with class `positive`/`negative`
  (`line_react_util.tl:621-640`). It is a rolling 12 months of maintenance+income, despite the "Last Year" label in the line window.
- Cost: `stepTimer=true` → `useStepStateTimer` (0.5 s); `false` → `useStepState` (every step). In lists, use `true`.
- Base usage (`G/statistics/statistic_lines.tl:232-245`; also `G/line_vehicle_mgmt/manager_window.tl:4007`, `G/entity_window/line/line_eow.script.tl:308`):
```lua
return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = {
  line_react_util.LineBalance{ entity = entity, stepTimer = true },
}}
```
- Surprise: the statistics sort value sums the line's *vehicles* (`calculateBalance(getLineVehicles(line), …)`,
  `statistic_lines.tl:286-291`), while the displayed cell passes `{line}`. The two may differ.
- Sibling: `LineTransported{entity, stepTimer}` → `logbook.getLogValuePerYear(entity, "itemsTransported")` (`line_react_util.tl:642-658`).

### 8.2 `line_react_util.ColorWidget{ entity, color?, tooltip?, onClick? }`
- Signature: `line_react_util.d.tl:51-57`. Colour dot. With `color == nil` it polls `COLOR` of `entity` by
  `react.onStepTimer` (0.5 s) (`line_react_util.tl:271-300`). With `onClick` it becomes a Button.
- Base usage (`G/line_vehicle_mgmt/manager_window.tl:2154-2162`):
```lua
children[#children + 1] = line_react_util.ColorWidget{
  tooltip = _("Open Line Window"),
  entity = entity,
  onClick = function() react.fireEvent(nil, "selectEntity", { entity = entity, stack = true }) end,
}
```
  Minimal form: `line_react_util.ColorWidget{ entity = lineEntity }` (`G/entity_window/vehicle/vehicle_eow.script.tl:925-927`).

### 8.3 `vehicle_react_util.ConditionIcon(vehicleEntity)` / `ConditionTextView(vehicleEntity)`
- Signature: `Recipe<Engine.Entity>` (positional arg, not a table) (`G/line_vehicle_mgmt/vehicle_react_util.d.tl:39-40`).
- Implementation (`vehicle_react_util.tl:51-72`): `useStepState` (every step) of
  `vehicle_util.getAvgMaintenanceState(v)` → `getConditionIcon`/`getConditionText`. It renders an icon Button with
  the text as tooltip, and a click fires `selectEntity{stack=false}`. `ConditionTextView` (`:39-49`) is a text link to the vehicle window (tab 1).
- Base usage: only commented out (`G/line_vehicle_mgmt/vehicle_list_react_util.tl:456`). Usage is positional:
```lua
builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = {
  vehicle_react_util.ConditionIcon(vehicleEntity),
}}
```
- Cost: per-step polling per instance. For long lists, compute the condition yourself in a timer state.

### 8.4 `entity_window_util.RatingBar{ … }`
- Params (`G/entity_window/entity_window_util.d.tl:208-222`): `icon`|`iconPath`, `tooltip`, `ratingText`,
  `getRatingLabel(level)`, `barTooltip`, `value` (0..1), `valueChange`, `numFractions` (**must be > 0**, logs an error
  otherwise), `snapValueToFractions`, `onClick`, `hideText`, `showIcon`.
- Colour class: from `value` (0 / ≤⅓ / ≤⅔ / >⅔ → `rating-bar-value-0/1/3/5`) (`entity_window_util.tl:33-58`). Pure render, no engine polling.
- Base usage (`G/entity_window/town_building/town_building.tl:177-190`):
```lua
return builtin.BoxLayout{ children = {
  entity_window_util.RatingBar{
    iconPath = "::/gui/line_vehicle_mgmt/icons/symbol_noise.tga",
    tooltip = _("Noise"),
    getRatingLabel = town_util.getRatingLabel,
    barTooltip = "...",
    value = mathutil.mapClamp(emissionDb, lower, upper, 1, 0),
    numFractions = 5,
    snapValueToFractions = true,
    onClick = function() react.fireEvent(nil, "openLayerRidge", { layer = "menu.layers.noiseButton", stack = true }) end,
    showIcon = true,
  },
}}
```

### 8.5 `gui_react_util.IconLabelIndicator{ … }`
- Params (`G/main/gui_react_util.d.tl:86-99`): `iconPath : string|{string}`, `label`, `richLabel`,
  `labelFontColor` ("Default"|"Warning"|"Error"|"Positive"|"Negative"|"Normal"|"Inferior"|"Poor", `:4-17`),
  `labelMode` ("Default"|"EntityWindow"|"EntityWindowPostfix"|"HudIconMain"|"HudIconLayer", `:20-26`), `indicatorIconPath`,
  `tooltip`, `iconTooltip`, `overlay`, `indicator`, `shippingState`, `useEmoteWithSatisfaction`.
- It is a thin recipe over `makeContentLabelIndictator(params)` (`gui_react_util.tl:330-332`), pure render.
- Base usage, the line window's Frequency chip (`G/entity_window/line/line_eow.script.tl:56-77`):
```lua
local frequency = state:old()                       -- seconds, from line_util.calculateFrequencySeconds
return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = {
  gui_react_util.IconLabelIndicator({
    iconPath = "::/gui/entity_window/icons/symbol_stop_watch.tga",
    label = frequency == 0 and "--" or api.util.formatSeconds(frequency),
    tooltip = lang_util.format(_("Frequency: {count}"), { count = api.util.formatMinutesSeconds(frequency) }),
  }),
}}
```
- Helpers next to it: `gui_react_util.integer2TextLayout(value, tag?)` (BoxLayout with a formatted int, `gui_react_util.tl:334-344`),
  `makeHorizontalSpacer()`, `makeHorizontalBox{…}`, `makeVerticalBox{…}` (`gui_react_util.d.tl:137-140`).

### 8.6 Notification widgets (see §5)
- `entity_window_util.NotificationWidget(entity)`: all persisting notifications of the entity as clickable cards
  (`entity_window_util.tl:2129-2160`, `useStepState` every step). Used as the first EOW plugin, e.g. `G/entity_window/line/line_eow.script.tl:29`.
- `line_react_util.ManagerNotificationWidget(entity)`: Problem/Caution `lvmIcon`s only (`line_react_util.tl:107-140`).
- `statistics_react_util.ProblemsCell`: DataTable cell. It needs `userParam.notificationState = {entity:{id}}` (`statistics_react_util.tl:346-366`).

### 8.7 `builtin.DataTable` + `builtin.ColumnDesc` + cell recipes
- `ColumnDescParam` (`scripts/scripts/builtin.d.tl:1137-1153`): `name`, `tooltip`, `path` (header icon),
  `headerStyleClass`, `weight`, `recipe` (cell recipe receiving `Builtin.TableCellParam {rowKey, colKey, userParam}`, `:1125-1129`),
  `getCompareValue(rowKey) → any` (C++ sort; strings use natural compare unless `forceLexicographicalStringComparison`).
  The base computes the value when the table sorts, either from the engine (`statistic_depots.tl:146-159`) or from
  the table's state (`getProblemsCompareValue` reads `tableState:old()`). A column whose cell shows data the
  table's own timer already read can sort by that copy, which is cheap and matches the cell (`cards.lua`, Waiting).
- `DataTableParam` (`builtin.d.tl:1160-1181`): `columns`, `rowKeys : {integer}`, `preferredInitialSelectionRowKey`,
  `disableSortKey`, `iaSort`, `compareFn` (deprecated, use `getCompareValue`), `userParam` (given only to
  newly created cells, existing cells are not updated), `fnUserFilter(rowKey)`, `initialSortColumn = {colIndex, asc}`,
  `onSortColumnChange`, `scrollPolicyHorizontal/Vertical`, `keyboardNavigation`. `columnWeights` has been removed.
  API: `scrollToRowKey(rowKey, forceTopAlign)` (`:1155-1158`).
- Base, condensed from `G/statistics/statistic_lines.tl:200-218, 376-457`:
```lua
local LineFrequencyCell = react.RegisterRecipe("UioLineFrequencyCell", function(params)   -- params.rowKey = line entity
  local entity = params.rowKey
  local frequencyState = engine_react_util.useStepStateTimer(function()
    return line_util.calculateFrequencySeconds(entity)
  end)
  return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = {
    builtin.TextView{ meta = { class = "font-scale-body", forceFocusable = true },
                      text = api.util.formatMinutesSeconds(frequencyState:old()) },
  }}
end)

local columns = {
  builtin.ColumnDesc{ name = _("Name"), recipe = LineLocationAndNameCell,
                      getCompareValue = function(e) return api.engine.util.getEntityName(e) end, weight = 5.44 },
  builtin.ColumnDesc{ path = "::/gui/statistics/icons/alert.tga", tooltip = _("Problems"),
                      recipe = statistics_react_util.ProblemsCell, getCompareValue = getProblemsCompareValue, weight = 0.75 },
  builtin.ColumnDesc{ name = _("Frequency"), recipe = LineFrequencyCell,
                      getCompareValue = line_util.calculateFrequencySeconds, weight = 1.9, headerStyleClass = "right-aligned" },
}
-- tableState = useStepState(function() return { keys = lineSystem.getLinesForPlayer(player), notificationsState = ... } end)
return builtin.FloatingLayout{ children = {            -- base root; a BoxLayout root works too
  builtin.FloatingLayoutChild{
    item = builtin.DataTable(react.ref(tableRef), {
      meta = { id = "menu.statistics.lines" },
      iaSort = "IA_OPTION1",
      columns = columns,
      rowKeys = tableState:old().keys,
      userParam = { notificationState = tableState:old().notificationsState },
      initialSortColumn = { 1, true },
      fnUserFilter = function(key) return tableState:old().filteredKeysMap[key] or false end,
    }),
  },
}}
```
- Cost: each cell runs its own `useStepStateTimer` (0.5 s). `getCompareValue` is called by C++ when sorting, and base
  computes heavy values there (`calculateCargoColumnDataForLine`, `calculateBalance`), so it is not cached.
  `styleClassRightAligned = "right-aligned"` (`statistic_lines.tl:15`).

### 8.8 `builtin.ScrollArea`
- Params (`builtin.d.tl:749-758`): `content`, `horizontalPolicy`/`verticalPolicy` (`builtin.type.ScrollBarPolicy.AsNeeded|AlwaysOff|…`),
  `disableGamepadNavigation`, `disableMouseScrolling`, `onScroll(Vec2i, Vec2i)`.
- Base (`G/entity_window/double_slip_switch.tl:547-558`): the content is a `Component` wrapping a layout.
```lua
builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = {
  builtin.ScrollArea{
    horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
    verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
    content = builtin.Component{ layout = builtin.BoxLayout{
      orientation = builtin.type.Orientation.Vertical, children = rows } },
  },
}}
```

### 8.9 `builtin.TabWidget` / `builtin.TabWidgetChild`
- `TabWidgetParam` (`builtin.d.tl:1086-1097`): `orientation` (`builtin.type.TabOrientation.North` default), `deselectAllowed`,
  `indicatorsScrollable`, `tabs : {TabWidgetChild}`, `showIndicators`, `onClose`, `initialValue` | `value` + `onValueChange(newValue)`.
- `TabWidgetChildParam` (`:1099-1107`): `localKey`, `indicator` (header node), `item` (page node), `value`
  (required, unique; use a string key, not an index).
- Base (`G/entity_window/town/town.tl:775-794, 806-818`):
```lua
local tabs = {
  builtin.TabWidgetChild{ localKey = "tab_lines", value = "Lines",
    indicator = builtin.TextView{ text = _("Lines") }, item = LinesPage{} },
  builtin.TabWidgetChild{ localKey = "tab_vehicles", value = "Vehicles",
    indicator = builtin.TextView{ text = _("Vehicles") }, item = VehiclesPage{} },
}
return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = {
  builtin.TabWidget{
    orientation = builtin.type.TabOrientation.North,
    deselectAllowed = false,
    value = tabState:old(),
    tabs = tabs,
    onValueChange = function(v) tabState:set(v) end,
  },
}}
```

### 8.10 `builtin.ToggleButtonGroup`
- Params (`builtin.d.tl:873-892`): `buttons : {{content, meta}}` (plain tables; `meta` is passed to the inner ToggleButton),
  `onValueChange(index, value)`, `deselectAllowed`, `layout` ("Horizontal"|"Vertical"|"Flow"|"Uniform"), `separators`,
  `initialSelected` | `selected` (1-based; -1 = none, only with `deselectAllowed`).
- Base (`G/entity_window/line/line_eow.script.tl:461-483`), bound to an engine value through `useStepState` + a command:
```lua
local items = {}
for i = 1, #priorities do
  items[#items + 1] = { meta = { tooltip = priorities[i].label },
                        content = builtin.ImageView{ path = priorities[i].icon } }
end
return builtin.BoxLayout{ children = {
  builtin.ToggleButtonGroup{
    buttons = items,
    selected = selectedPriorityState:old(),
    onValueChange = function(index, _) commitPriority(index) end,
  },
}}
```

### 8.11 `builtin.CheckBox`
- Params (`builtin.d.tl:1024-1031`): `onValueChange(integer)`, `triStateSupport`, `initialValue` (uncontrolled) | `value`
  (controlled, 0/1/2), `label` (clicking it toggles), `moveBoxRight`.
- Base (`G/entity_window/town_building/town_building.tl:205-224`): a controlled checkbox bound to a command.
```lua
local blockedState, blockedCommit = engine_react_util.useStepState(makeBlockedDevelopmentState,
  function(newState) return api.cmd.makeTownBuildingSetBlockedDevelopmentCmd(params.entityId, newState), nil end)
return builtin.BoxLayout{ children = {
  builtin.CheckBox{
    label = _("Historic Preservation"),
    meta = { tooltip = _("Preserves the appearance of the building but it can still level up.") },
    onValueChange = function(value) blockedCommit(value == 1) end,
    value = blockedState:old() and 1 or 0,
  },
}}
```

### 8.12 Polling hooks used by all of the above (`G/main/engine_react_util.d.tl:3-49`)
- `useStepState(get, makeCommand?, equals?, onChange?, once?)` → `(state, commit)`: re-evaluates every step.
  `commit(value[, cmd, cb])` sends the command and keeps an optimistic local value.
- `useStepStateTimer(get, interval = 0.5 s, equals = deepEquals)` → `state` (`engine_react_util.tl:126-152`, via `react.onStepTimer`).
- `useStepStateTimerWithCommit(get, interval, makeCommand, …)`: the notification ridge uses it (`NM/gui/notification_popups.tl:277`).
- `useStepStateParallel(useFnName, params, finalize, …)` / `useStepStateParallelSimple(useFnName, params)`: the work
  runs in another thread, and the result is applied next frame.

## 9. Load order and other mods

Observed in game (build 40408, 2026-10-05, with 13 mod.io mods active in both orders).

### 9.1 Load order
- The mod list's activation order (the numbers in the game's mod list, `StartGameParams.mods`, a savegame's
  mod list) is the order in which mods load. Generic resource ids follow it: the game's own resources first,
  then mod by mod. `api.res.genericRep.getAllOfType(type)` returns ids, `getName(id)` names such as
  `ui_overhaul_1::/ui_overhaul/gui/entry.res` (`::/...` for the game's). A mod's smallest id gives its
  position (`gui/priority.lua`).
- The game has no rule of its own for two mods changing the same thing: `react-replacement-config`s run
  sorted by `order` (`bootstrap_game.tl:22`, `table.sort`, not stable for equal orders), the last
  `ReplaceRecipe` of a recipe wins, and module-field wraps nest in the order the configs ran.
- `api.engine.config.getModParams()` lists every active mod with its params (an empty table for a mod
  without params); it is readable in a replacement config, before the UI starts. A Button param's value is
  the 1-based index of the chosen value.

### 9.2 Who owns a function
- The debug library is there in the GUI state (`debug.getinfo`, `debug.getupvalue`); `pcall`/`xpcall` too.
- `debug.getinfo(fn, "S").source` is `<mod id>::/path.lua` for a module loaded with `require` (`::/path`
  for the game's own) and the file's path on disk for a resource script loaded by the engine (a
  `.script.lua` a res points at), e.g. `C:/Users/Public/mod.io/10640/mods/<id>/content/...` or
  `.../staging_area/<folder>/content/...`. `getCurrentModId()` inside a doReplaceFn names the mod whose
  file is on the require stack, not the config's mod.
- A recipe registered with `react.RegisterRecipe` is a wrapper defined in `react.lua`: its source does not
  tell the mod. Record the caller of `ReplaceRecipe` instead (the first frame on the stack from a mod file).
- The `replacementApi` table is one table handed to every config in turn: a config that runs first can wrap
  its `ReplaceRecipe` and see every later call.
- `react.fireEvent` is `api.gui.react.fireEvent`, an engine function: `type()` need not be `"function"`.

### 9.3 Window and node positions
- `nodeRef:getPosition(gravityX, gravityY)` returns parts of the screen (0..1), not pixels; a window's
  `initialX`/`initialY` are taken the same way, as the window's top left corner (a value above 1, e.g. a
  pixel count, is clamped to the edge). `api.gui.camera.getSize()` gives the screen in pixels.
- The game keeps a new window on the screen with the size it has before its content is laid out. A popover
  opened near the right or bottom edge then reaches past it as its rows fill it (opened at 0.9 on a 3440x1440
  screen, its content spans 0.829..1.047). Measure the content a few steps after it opened
  (`getPosition(0, 0)` and `(1, 1)` of a node inside it, in `react.onStep`) and open it again further left
  and up (`terminals.placement`).
- An entity window's title bar shows the pin button once the mouse is over the window (`pinnable`, set by
  `view_manager.tl` with mouse input). It is added before the close button, so everything right-aligned before
  it, the window's `header` slot included, moves left by its width (39 pixels at 3440x1440): a button aimed at
  from outside the window moves away under the cursor as it comes in, and its neighbour on the right takes the
  click (observed in game, build 40408). Buttons there that must not take each other's clicks go at the left
  of the header, before a title that fills the row (`minimize.lua`). A `TextView` with gravity 0 keeps its
  natural width: a long title then runs over the title bar's buttons; with gravity -1 it is cut short.
- The testbench (a game script with `guiUpdate`) runs in another Lua state than the mod's recipes:
  `require` of a mod module there loads a second copy, and its recipes fail to register. A check reads the
  component tree (`api.gui.byId`) and the log; a debug event of the mod logs what the check needs (and asks
  `run.sh` for a real click with `[testbench] CLICK x y`, as `minimize.lua` does on `uio.debug.header`).

- `builtin.Component{ layout = X }`: `X` must be a layout builtin (`builtin.BoxLayout{...}` ...). A recipe there (even one whose root is a layout) crashes the game natively, without a Lua error: "Item of Component must be a layout" (`react_builtin.cpp:564`, observed in game 2026-10, build 40408). Put the recipe inside a `BoxLayout`. `make lint` rejects `layout = <not builtin>`.
