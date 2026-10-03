--- Reads the game into the plain snapshot that core/health.lua works on.
-- The only module besides the GUI that touches the engine API. Runs inside timer callbacks, so it
-- must not call GUI-thread-only APIs (not even `_`): texts stay untranslated English keys of the
-- base game's strings and the GUI translates them with `_()` when it renders.
-- API references: docs/api_cookbook.md.
-- @module ui_overhaul.engine.snapshot
local snapshot = {}

local lifespan_by_model = {} -- model id -> lifespan in game ms (model data does not change)

--- Engine calls to leave out, for bisecting native crashes: { line_problems = true, cashflow = true }.
snapshot.skip = {}

--- Number of upcoming snapshots that log each engine call before making it. Native crashes leave no
-- Lua error, so the last trace line in stdout.txt names the call that crashed.
snapshot.trace = 0

local function trace(step)
	if snapshot.trace > 0 then debugPrint("[ui_overhaul] trace ", step) end
end

local function carrier_names()
	local carrier = api.type.enum.Carrier
	return {
		[carrier.ROAD] = "ROAD", [carrier.TRAM] = "TRAM", [carrier.RAIL] = "RAIL",
		[carrier.WATER] = "WATER", [carrier.AIR] = "AIR",
	}
end

local function game_time()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

local function lifespan_ms(model_id)
	local lifespan = lifespan_by_model[model_id]
	if lifespan == nil then
		local maintenance = api.res.modelRep.get(model_id).metadata.maintenance
		lifespan = maintenance and maintenance.lifespan and maintenance.lifespan * 1000 or 0
		lifespan_by_model[model_id] = lifespan
	end
	return lifespan
end

--- Purchase time of the oldest part and the lifespan of that part (base: vehicle_util.getMinPurchaseTimeAndLifespan).
local function purchase_and_lifespan(transport_vehicle)
	local purchase, lifespan
	for _i, part in ipairs(transport_vehicle.transportVehicleConfig.vehicles) do
		local part_lifespan = lifespan_ms(part.part.modelId)
		if purchase == nil or part.purchaseTime < purchase
			or (part.purchaseTime == purchase and part_lifespan < lifespan) then
			purchase, lifespan = part.purchaseTime, part_lifespan
		end
	end
	return purchase, lifespan
end

-- Short reason texts: the same strings as the base notification types (line_warning.script.tl), so
-- the game's translations apply when the GUI passes them through _().
local function issue_text(issue_type)
	local types = api.type.LineIssue.Type
	if issue_type == types.LineCargoConfig then return "The line isn't configured to load any cargo." end
	return "Some Cargo Type Configurations of This Line Are Clashing"
end

local function problem_text(problem)
	local p = api.type.enum.LineProblem
	if problem == p.ZERO_OR_ONE_STATION then return "Line Contains Too Few Stations" end
	if problem == p.DOUBLE_STATIONS then return "A Station Appears Consecutively Twice" end
	if problem == p.INCOMPATIBLE_STATIONS then return "Stations Are Incompatible Due to Conflicting Stops" end
	if problem == p.BAD_ALTERNATIVE_TERMINAL then return "Could Not Connect Alternative Terminals" end
	return "Could Not Connect Stations"
end

--- { [line] = { {severity, text} } } from the engine's line problems (no path ...) and issues (cargo setup).
local function line_issues(player)
	local result = {}
	local function add(line, severity, text)
		result[line] = result[line] or {}
		table.insert(result[line], { severity = severity, text = text })
	end
	local nothing = api.type.enum.LineProblem.NOTHING
	trace("getLineProblems")
	for _i, entry in ipairs(snapshot.skip.line_problems and {} or api.engine.util.line.getLineProblems()) do
		if entry[2] ~= nothing then add(entry[1], "problem", problem_text(entry[2])) end
	end
	trace("getLinesIssues")
	for line, issues in pairs(api.engine.util.line.getLinesIssues(player, false)) do
		local seen = {}
		for _i, issue in ipairs(issues) do
			local text = issue_text(issue.type)
			if not seen[text] then
				seen[text] = true
				add(line, "caution", text)
			end
		end
	end
	return result
end

--- Share of the current capacity in use (base statistics "Utilization" is the same idea per cargo type).
local function utilization(line)
	local used, capacity = 0, 0
	for _i, usage in pairs(api.engine.util.line.getLineCapacityUsages(line, false) or {}) do
		used, capacity = used + (usage.used or 0), capacity + (usage.capacity or 0)
	end
	if capacity <= 0 then return nil end
	return used / capacity
end

local function finance(player, now)
	local f = api.engine.util.finance
	local month = api.util.getDefaultMonthDuration()
	trace("finance")
	return {
		cash = f.getPlayersBalance(player), -- nil = infinite money
		earnings_ytd = f.calculateEarnings(player),
		cashflow_month = not snapshot.skip.cashflow
			and f.calculateBalance({ player }, math.max(now - month, 0), now, false) or nil,
		cashflow_last_month = not snapshot.skip.cashflow
			and f.calculateBalance({ player }, math.max(now - 2 * month, 0), math.max(now - month, 0), false) or nil,
	}
end

--- Plain snapshot of finance, lines and vehicles (see core/health.lua for the shape).
function snapshot.take()
	local player = api.engine.util.getPlayer()
	local now = game_time()
	local year = api.util.getDefaultYearDuration()
	local carriers = carrier_names()
	local issues = line_issues(player)
	local vehicle_system = api.engine.system.transportVehicleSystem

	local result = { time = now, finance = finance(player, now), lines = {}, vehicles = {} }
	trace("lines")
	local line_names = {}
	for _i, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(player)) do
		local vehicles = vehicle_system.getLineVehicles(line)
		local carrier
		if vehicles[1] then
			local tv = api.engine.getComponent(vehicles[1], api.type.ComponentType.TRANSPORT_VEHICLE)
			carrier = tv and carriers[tv.carrier]
		end
		local name = api.engine.util.getEntityName(line)
		line_names[line] = name
		result.lines[#result.lines + 1] = {
			id = line,
			name = name,
			carrier = carrier,
			vehicle_count = #vehicles,
			balance = api.engine.util.finance.calculateBalance({ line }, math.max(now - year, 0), now, true),
			utilization = utilization(line),
			issues = issues[line] or {},
		}
	end

	trace("vehicles")
	local states = api.type.enum.TransportVehicleState
	local own = { requireOwnedByPlayer = player }
	for _i, vehicle in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE, own)) do
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
		if tv then
			local purchase, lifespan = purchase_and_lifespan(tv)
			local on_line = tv.state == states.EN_ROUTE or tv.state == states.AT_TERMINAL
			result.vehicles[#result.vehicles + 1] = {
				id = vehicle,
				name = api.engine.util.getEntityName(vehicle),
				line = on_line and tv.line or nil,
				line_name = on_line and line_names[tv.line] or nil,
				age_years = purchase and (now - purchase) / year or nil,
				lifespan_years = lifespan and lifespan > 0 and lifespan / year or nil,
				no_path = tv.noPath == true,
				stopped = tv.userStopped == true,
				in_depot = tv.state == states.IN_DEPOT,
			}
		end
	end
	trace("done")
	snapshot.trace = math.max(snapshot.trace - 1, 0)
	return result
end

return snapshot
