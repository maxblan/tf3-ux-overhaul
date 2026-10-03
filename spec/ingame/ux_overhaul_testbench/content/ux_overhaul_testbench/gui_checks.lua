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
		wait = 120,
		shot = "game_bar",
		check = function()
			local player = api.engine.util.getPlayer()
			local lines = api.engine.system.lineSystem.getLinesForPlayer(player)
			local vehicles = api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE)
			return true, string.format("lines=%d vehicles=%d", #lines, #vehicles)
		end,
	},
	{
		name = "statistics_lines_tab",
		act = function() api.gui.fireReactEvent("openStatisticsWindow", "Line") end,
		wait = 90,
		shot = "statistics_lines",
		check = function()
			return visible("uxo.statistics.totals"), "totals visible=" .. tostring(visible("uxo.statistics.totals"))
		end,
	},
	{
		name = "statistics_quick_filter_losing",
		act = function() api.gui.fireReactEvent("uxo.statistics.filter", "losing") end,
		wait = 90,
		shot = "statistics_lines_losing",
		check = function() return visible("uxo.statistics.totals"), "filtered table shown" end,
	},
	{
		name = "windows_side_by_side",
		act = function(ctx)
			api.gui.fireReactEvent("uxo.statistics.filter", "all")
			ctx.card_line = busiest_line()
			api.gui.fireReactEvent("openVehicleManager", { openWithLineEntity = ctx.card_line })
		end,
		wait = 120,
		shot = "statistics_and_line_manager",
		check = function()
			local stats, lvm = visible("menu.statistics.window"), visible("menu.management")
			return stats and lvm, string.format("statistics=%s line manager=%s", tostring(stats), tostring(lvm))
		end,
	},
	{
		name = "map_click_keeps_windows",
		act = function(ctx)
			local component = ctx.card_line and api.engine.getComponent(ctx.card_line, api.type.ComponentType.LINE)
			ctx.card_station = component and component.stops[1] and component.stops[1].stationGroup
			-- what a map click does on PC: select without stacking
			if ctx.card_station then api.gui.fireReactEvent("selectEntity", { entity = ctx.card_station, stack = false }) end
		end,
		wait = 90,
		shot = "map_click_with_windows",
		check = function()
			local stats, lvm = visible("menu.statistics.window"), visible("menu.management")
			return stats and lvm, string.format("statistics=%s line manager=%s", tostring(stats), tostring(lvm))
		end,
	},
	{
		name = "statistics_quick_filter_problems",
		act = function() api.gui.fireReactEvent("uxo.statistics.filter", "problems") end,
		wait = 90,
		shot = "statistics_lines_problems",
		check = function() return visible("uxo.statistics.totals"), "filtered table shown" end,
	},
	{
		name = "line_manager_remembers_line",
		act = function()
			api.gui.fireReactEvent("closeStatisticsWindow", nil)
			api.gui.fireReactEvent("closeVehicleManager", nil)
		end,
		wait = 30,
		check = function()
			api.gui.fireReactEvent("openVehicleManager", {}) -- like the game bar button
			return true, "reopened without a target"
		end,
	},
	{
		name = "line_manager_remembered_shot",
		wait = 60,
		shot = "line_manager_remembered",
		check = function()
			return visible("menu.management"), "line manager visible=" .. tostring(visible("menu.management"))
		end,
	},
	{
		name = "clone_many_asks_first",
		act = function(ctx)
			local vehicles = ctx.card_line and line_vehicles(ctx.card_line) or {}
			ctx.clone_before = #vehicles
			if #vehicles >= 2 then api.gui.fireReactEvent("uxo.debug.clone", { vehicles[1], vehicles[2] }) end
		end,
		wait = 300,
		check = function(ctx)
			if (ctx.clone_before or 0) < 2 then return true, "skipped: fewer than 2 vehicles" end
			local after = #line_vehicles(ctx.card_line)
			return after == ctx.clone_before, string.format("vehicles %d -> %d (expect no purchase before confirming)",
				ctx.clone_before, after)
		end,
	},
	{
		name = "line_window_card",
		act = function(ctx)
			api.gui.fireReactEvent("closeVehicleManager", nil)
			if ctx.card_line then api.gui.fireReactEvent("selectEntity", { entity = ctx.card_line, stack = false }) end
		end,
		wait = 90,
		shot = "line_window",
		check = function(ctx)
			if not ctx.card_line then return true, "skipped: no line" end
			return visible("uxo.card.line.stops"), "line card visible=" .. tostring(visible("uxo.card.line.stops"))
		end,
	},
	{
		name = "manage_line_keeps_line_window",
		act = function(ctx)
			if ctx.card_line then api.gui.fireReactEvent("openVehicleManager", { openWithLineEntity = ctx.card_line }) end
		end,
		wait = 120,
		shot = "line_window_and_line_manager",
		check = function(ctx)
			if not ctx.card_line then return true, "skipped: no line" end
			local line_window, lvm = visible("uxo.card.line.stops"), visible("menu.management")
			return line_window and lvm, string.format("line window=%s line manager=%s", tostring(line_window), tostring(lvm))
		end,
	},
	{
		name = "reference_station_window",
		act = function(ctx)
			api.gui.fireReactEvent("closeVehicleManager", nil)
			local component = ctx.card_line and api.engine.getComponent(ctx.card_line, api.type.ComponentType.LINE)
			ctx.card_station = component and component.stops[1] and component.stops[1].stationGroup
			if ctx.card_station then api.gui.fireReactEvent("selectEntity", { entity = ctx.card_station, stack = false }) end
		end,
		wait = 90,
		shot = "station_window",
		check = function() return true, "reference screenshot" end,
	},
	{
		name = "reference_vehicle_window",
		act = function(ctx)
			ctx.card_vehicle = ctx.card_line and oldest_vehicle(ctx.card_line)
			if ctx.card_vehicle then api.gui.fireReactEvent("selectEntity", { entity = ctx.card_vehicle, stack = false }) end
		end,
		wait = 90,
		shot = "vehicle_window",
		check = function() return true, "reference screenshot" end,
	},
	{
		name = "construction_rail_menu",
		act = function()
			api.gui.fireReactEvent("closeAllWindows", nil)
			api.gui.fireReactEvent("constructionMenuSetTab", { tabIndex = 2 })
		end,
		wait = 90,
		shot = "construction_rail",
		check = function() return true, "screenshot" end,
	},
	{
		name = "construction_tracks_menu",
		act = function()
			api.gui.fireReactEvent("clearToolStack", nil)
			api.gui.fireReactEvent("constructionMenuSetTab", { tabIndex = 17 })
		end,
		wait = 90,
		shot = "construction_tracks",
		check = function() return true, "screenshot" end,
	},
	{
		name = "configure_opens_module_tab",
		act = function(ctx)
			api.gui.fireReactEvent("clearToolStack", nil)
			local component = ctx.card_station
				and api.engine.getComponent(ctx.card_station, api.type.ComponentType.STATION_GROUP)
			local station = component and component.stations[1]
			local construction = station and api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station)
			ctx.configure = construction
			-- what the station window's "Configure" button does (entity_window_util.makeConfigureOnClickFunction)
			if construction and construction >= 0 then
				api.gui.fireReactEvent("setModuleBuilderEntity", construction)
				api.gui.fireReactEvent("constructionMenuSetTab", { tabIndex = 9, allowStacking = true })
			end
		end,
		wait = 120,
		shot = "configure_modules",
		check = function(ctx) return true, "construction=" .. tostring(ctx.configure) end,
	},
	{
		name = "action_add_vehicle",
		act = function(ctx)
			api.gui.fireReactEvent("clearToolStack", nil)
			api.gui.fireReactEvent("closeAllWindows", nil)
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
