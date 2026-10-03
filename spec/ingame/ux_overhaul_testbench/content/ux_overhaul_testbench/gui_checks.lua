--- In-game GUI checks, run in order by testbench.script.lua on the GUI thread (guiUpdate).
--
-- Each check has:
--   name           unique name, shown in the PASS/FAIL line
--   act(ctx)       optional; drives the GUI (fires react events, selects entities ...)
--   wait           guiUpdate calls (about one per frame) between act and check
--   check(ctx)     returns passed (boolean) and a details string
--
-- `ctx` is a plain table kept in the GUI state; checks may store values in it (serialisable only).
-- Checks that need lines pass as "skipped" on the small new map; run them with
-- `make test-ingame SAVE="<savegame>"`.
-- @module ux_overhaul_testbench.gui_checks

local function visible(id)
	return api.gui.byId.isVisibleRecursive(id)
end

local function line_vehicles(line)
	return api.engine.system.transportVehicleSystem.getLineVehicles(line)
end

--- The player's line with the most vehicles, or nil.
local function busiest_line()
	local best, best_count = nil, 0
	for _i, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		local count = #line_vehicles(line)
		if count > best_count then best, best_count = line, count end
	end
	return best, best_count
end

local function oldest_vehicle(line)
	local best, best_time
	for _i, vehicle in ipairs(line_vehicles(line)) do
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
		local t = math.huge
		for _j, part in ipairs(tv.transportVehicleConfig.vehicles) do t = math.min(t, part.purchaseTime) end
		if best == nil or t < best_time then best, best_time = vehicle, t end
	end
	return best
end

local checks = {
	{
		name = "gui_fixture_facts",
		wait = 60,
		check = function()
			local player = api.engine.util.getPlayer()
			local lines = api.engine.system.lineSystem.getLinesForPlayer(player)
			local vehicles = api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE)
			return true, string.format("lines=%d vehicles=%d", #lines, #vehicles)
		end,
	},
	{
		name = "status_strip_visible",
		wait = 120,
		check = function()
			return visible("uxo.status.problems"), "problems chip visible=" .. tostring(visible("uxo.status.problems"))
				.. " cashflow chip visible=" .. tostring(visible("uxo.status.cashflow"))
		end,
	},
	{
		name = "launcher_visible",
		check = function()
			local shown = api.gui.byId.isVisible("uxo.launcher.control_center")
			return shown, "control center button visible=" .. tostring(shown)
		end,
	},
	{
		name = "control_center_problems_tab",
		act = function() api.gui.fireReactEvent("uxo.open", { tab = "problems" }) end,
		wait = 60,
		check = function()
			return visible("uxo.cc.window") and visible("uxo.cc.problems"),
				string.format("window=%s problems=%s", tostring(visible("uxo.cc.window")), tostring(visible("uxo.cc.problems")))
		end,
	},
	{
		name = "control_center_lines_tab",
		act = function() api.gui.fireReactEvent("uxo.open", { tab = "lines", filter = "all" }) end,
		wait = 60,
		check = function()
			return visible("uxo.cc.filter.losing") and visible("uxo.cc.lines"),
				string.format("filters=%s lines=%s", tostring(visible("uxo.cc.filter.losing")), tostring(visible("uxo.cc.lines")))
		end,
	},
	{
		name = "line_window_card",
		act = function(ctx)
			ctx.card_line = busiest_line()
			if ctx.card_line then api.gui.fireReactEvent("selectEntity", { entity = ctx.card_line, stack = true }) end
		end,
		wait = 90,
		check = function(ctx)
			if not ctx.card_line then return true, "skipped: no line" end
			return visible("uxo.card.line.vehicles"), "line card visible=" .. tostring(visible("uxo.card.line.vehicles"))
		end,
	},
	{
		name = "station_window_card",
		act = function(ctx)
			local component = ctx.card_line and api.engine.getComponent(ctx.card_line, api.type.ComponentType.LINE)
			ctx.card_station = component and component.stops[1] and component.stops[1].stationGroup
			if ctx.card_station then api.gui.fireReactEvent("selectEntity", { entity = ctx.card_station, stack = true }) end
		end,
		wait = 90,
		check = function(ctx)
			if not ctx.card_station then return true, "skipped: no station" end
			return visible("uxo.card.station.lines"), "station card visible=" .. tostring(visible("uxo.card.station.lines"))
		end,
	},
	{
		name = "vehicle_window_card",
		act = function(ctx)
			ctx.card_vehicle = ctx.card_line and oldest_vehicle(ctx.card_line)
			if ctx.card_vehicle then api.gui.fireReactEvent("selectEntity", { entity = ctx.card_vehicle, stack = true }) end
		end,
		wait = 90,
		check = function(ctx)
			if not ctx.card_vehicle then return true, "skipped: no vehicle" end
			return visible("uxo.card.vehicle.age"), "vehicle card visible=" .. tostring(visible("uxo.card.vehicle.age"))
		end,
	},
	{
		name = "action_add_vehicle",
		act = function(ctx)
			ctx.line, ctx.before = busiest_line()
			if ctx.line then api.gui.fireReactEvent("uxo.action", { name = "add_vehicle", entity = ctx.line }) end
		end,
		wait = 600,
		check = function(ctx)
			if not ctx.line then return true, "skipped: no line with vehicles" end
			local after = #line_vehicles(ctx.line)
			return after == ctx.before + 1, string.format("line %d vehicles %d -> %d", ctx.line, ctx.before, after)
		end,
	},
	{
		name = "action_remove_vehicle",
		act = function(ctx)
			ctx.vehicle = ctx.line and oldest_vehicle(ctx.line)
			if ctx.vehicle then api.gui.fireReactEvent("uxo.action", { name = "remove_vehicle", entity = ctx.line }) end
		end,
		wait = 300,
		check = function(ctx)
			if not ctx.vehicle then return true, "skipped: no line with vehicles" end
			local tv = api.engine.getComponent(ctx.vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
			if not tv then return true, "vehicle already sold" end
			local going = tv.state == api.type.enum.TransportVehicleState.GOING_TO_DEPOT
				or tv.state == api.type.enum.TransportVehicleState.IN_DEPOT
			return going and tv.sellOnArrival == true, string.format("vehicle %d state=%s sellOnArrival=%s",
				ctx.vehicle, tostring(tv.state), tostring(tv.sellOnArrival))
		end,
	},
}

-- Crash probe (gui/probe.script.lua): set PROBE = true to open its window variants first.
local PROBE = false
if PROBE then
	local probes = {}
	for variant = 1, 5 do
		probes[#probes + 1] = {
			name = "probe_variant_" .. variant,
			act = function() api.gui.fireReactEvent("uxo.probe", variant) end,
			wait = 120,
			check = function() return api.gui.byId.isVisibleRecursive("probe.window"), "window visible" end,
		}
	end
	for _i, check in ipairs(checks) do probes[#probes + 1] = check end
	return probes
end

return checks
