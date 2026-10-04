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
-- @module ui_overhaul_testbench.gui_checks

local fixture = require("/ui_overhaul_testbench/fixture.lua")

-- Mods the run added (run.sh --with-mod): checks expect what they change.
local with_mod = {}
for _i, name in ipairs(fixture.mods or {}) do with_mod[name] = true end
-- Replaces the station window and brings its own terminal buttons there.
local TERMINAL_SELECTOR = with_mod.terminal_selector
-- Takes over every popover named TerminalSelection, the mod's included.
local EASY_TERMINALS = with_mod.zhenya_easy_terminal_assignment

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

local function stops_card(line)
	return line and visible("uio.card.line.stops." .. tostring(line))
end

--- A terminal of the first stop's station group that is neither preferred nor alternative: station
-- and terminal (1-based), or nil.
local function free_terminal(line)
	local stop = api.engine.getComponent(line, api.type.ComponentType.LINE).stops[1]
	local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
	for s, station_entity in ipairs(group.stations) do
		local station = api.engine.getComponent(station_entity, api.type.ComponentType.STATION)
		for t = 1, #station.terminals do
			local used = stop.station == s - 1 and stop.terminal == t - 1
			for _i, alternative in ipairs(stop.alternativeTerminals) do
				if alternative.station == s - 1 and alternative.terminal == t - 1 then used = true end
			end
			if not used then return s, t end
		end
	end
end

--- Number of alternative terminals of the first stop of `line`.
local function alternatives(line)
	return #api.engine.getComponent(line, api.type.ComponentType.LINE).stops[1].alternativeTerminals
end

--- Any player line other than `line`.
local function other_line(line)
	for _i, candidate in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		if candidate ~= line then return candidate end
	end
end

--- Composition key of a vehicle, as lvm_models.model_key builds it.
local function model_key(vehicle)
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	if not tv then return nil end
	local counts, order = {}, {}
	for _i, part in ipairs(tv.transportVehicleConfig.vehicles) do
		local id = part.part.modelId
		if not counts[id] then order[#order + 1] = id end
		counts[id] = (counts[id] or 0) + 1
	end
	table.sort(order)
	local parts = {}
	for i, id in ipairs(order) do parts[i] = id .. "x" .. counts[id] end
	return table.concat(parts, ",")
end

--- A player line whose list shows the model row: two or more models on the line, or a model that
-- another line uses too. Returns the line and a description, or nil.
local function model_row_line()
	local lines = api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
	local key_lines = {} -- key -> number of lines using it
	local line_keys = {}
	for _i, line in ipairs(lines) do
		local keys, count = {}, 0
		for _j, v in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
			local key = model_key(v)
			if key and not keys[key] then keys[key] = true count = count + 1 end
		end
		line_keys[line] = { keys = keys, count = count }
		for key in pairs(keys) do key_lines[key] = (key_lines[key] or 0) + 1 end
	end
	for _i, line in ipairs(lines) do
		if line_keys[line].count >= 2 then return line, "models=" .. line_keys[line].count end
	end
	for _i, line in ipairs(lines) do
		for key in pairs(line_keys[line].keys) do
			if key_lines[key] >= 2 then return line, "model shared with another line" end
		end
	end
	return nil
end

--- A player line with one model that no other line uses (the row stays hidden), or nil.
local function single_model_line()
	local lines = api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
	local key_lines, line_key = {}, {}
	for _i, line in ipairs(lines) do
		local keys, count, last = {}, 0, nil
		for _j, v in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
			local key = model_key(v)
			if key and not keys[key] then keys[key] = true count = count + 1 last = key end
		end
		if count == 1 then line_key[line] = last end
		for key in pairs(keys) do key_lines[key] = (key_lines[key] or 0) + 1 end
	end
	for _i, line in ipairs(lines) do
		if line_key[line] and key_lines[line_key[line]] == 1 then return line end
	end
	return nil
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

--- The vehicle is still there and not on its way to be sold.
local function kept(vehicle)
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	return tv ~= nil and tv.sellOnArrival ~= true
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
			return visible("uio.statistics.totals"), "totals visible=" .. tostring(visible("uio.statistics.totals"))
		end,
	},
	{
		name = "statistics_quick_filter_losing",
		act = function() api.gui.fireReactEvent("uio.statistics.filter", "losing") end,
		wait = 90,
		shot = "statistics_lines_losing",
		check = function() return visible("uio.statistics.totals"), "filtered table shown" end,
	},
	{
		name = "statistics_vehicles_old",
		act = function()
			api.gui.fireReactEvent("openStatisticsWindow", "Vehicle")
			api.gui.fireReactEvent("uio.statistics.vehicles.filter", "old")
		end,
		wait = 120,
		shot = "statistics_vehicles_old",
		check = function()
			return visible("uio.statistics.vehicles.totals"),
				"vehicles totals visible=" .. tostring(visible("uio.statistics.vehicles.totals"))
		end,
	},
	{
		name = "statistics_stations_nolines",
		act = function()
			api.gui.fireReactEvent("uio.statistics.vehicles.filter", "all")
			api.gui.fireReactEvent("openStatisticsWindow", "Station")
			api.gui.fireReactEvent("uio.statistics.stations.filter", "nolines")
		end,
		wait = 120,
		shot = "statistics_stations_nolines",
		check = function()
			return visible("uio.statistics.stations.totals"),
				"stations totals visible=" .. tostring(visible("uio.statistics.stations.totals"))
		end,
	},
	{
		name = "statistics_stations_crowded",
		act = function() api.gui.fireReactEvent("uio.statistics.stations.filter", "crowded") end,
		wait = 90,
		shot = "statistics_stations_crowded",
		check = function() return visible("uio.statistics.stations.totals"), "crowded filter" end,
	},
	{
		name = "statistics_warehouses",
		act = function()
			api.gui.fireReactEvent("uio.statistics.stations.filter", "all")
			api.gui.fireReactEvent("openStatisticsWindow", "Warehouse")
		end,
		wait = 120,
		shot = "statistics_warehouses",
		check = function()
			local shown = visible("uio.statistics.warehouses.totals")
			-- the shot: the quick-filter bar has the Lines tab's spacing and margins (statistics_common.css.lua)
			return shown, "warehouses totals visible=" .. tostring(shown)
		end,
	},
	{
		name = "windows_side_by_side",
		act = function(ctx)
			api.gui.fireReactEvent("uio.statistics.filter", "all")
			api.gui.fireReactEvent("uio.statistics.stations.filter", "all")
			api.gui.fireReactEvent("openStatisticsWindow", "Line")
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
		act = function() api.gui.fireReactEvent("uio.statistics.filter", "problems") end,
		wait = 90,
		shot = "statistics_lines_problems",
		check = function() return visible("uio.statistics.totals"), "filtered table shown" end,
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
			if #vehicles >= 2 then api.gui.fireReactEvent("uio.debug.clone", { vehicles[1], vehicles[2] }) end
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
		name = "replace_many_asks_first",
		act = function(ctx)
			local vehicles = ctx.card_line and line_vehicles(ctx.card_line) or {}
			if #vehicles >= 2 then api.gui.fireReactEvent("uio.debug.replace", { vehicles[1], vehicles[2] }) end
		end,
		wait = 60,
		shot = "line_manager_replace_question",
		check = function() return visible("menu.management"), "line manager open with the question" end,
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
			return stops_card(ctx.card_line), "line card visible=" .. tostring(stops_card(ctx.card_line))
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
			local line_window, lvm = stops_card(ctx.card_line), visible("menu.management")
			return line_window and lvm, string.format("line window=%s line manager=%s", tostring(line_window), tostring(lvm))
		end,
	},
	{
		-- Two line windows side by side: each Stops card needs its own id (run.sh fails on React errors).
		name = "two_line_windows",
		act = function(ctx)
			api.gui.fireReactEvent("closeVehicleManager", nil)
			ctx.second_line = other_line(ctx.card_line)
			if ctx.second_line then api.gui.fireReactEvent("selectEntity", { entity = ctx.second_line, stack = true }) end
		end,
		wait = 90,
		shot = "two_line_windows",
		check = function(ctx)
			if not ctx.second_line then return true, "skipped: only one line" end
			local first, second = stops_card(ctx.card_line), stops_card(ctx.second_line)
			return first and second, string.format("first=%s second=%s", tostring(first), tostring(second))
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
		check = function(ctx)
			if not ctx.card_vehicle then return true, "skipped: no vehicle" end
			-- the Performance card exists for powered rail and road vehicles (not for every line)
			local card = visible("uio.vehicle.performance." .. tostring(ctx.card_vehicle))
			return true, "performance card visible=" .. tostring(card)
		end,
	},
	{
		-- the minimize button in the title bar, then the window folded to it
		name = "entity_window_minimize",
		act = function() api.gui.fireReactEvent("uio.debug.minimize_all", nil) end,
		wait = 30,
		shot = "vehicle_window_minimized",
		check = function(ctx)
			if not ctx.card_vehicle then return true, "skipped: no vehicle" end
			local window = visible("temp.view.entity_" .. tostring(ctx.card_vehicle))
			return window, "window still open=" .. tostring(window) .. " (see the folded window in the screenshot)"
		end,
	},
	{
		name = "entity_window_restore",
		act = function() api.gui.fireReactEvent("uio.debug.minimize_all", nil) end,
		wait = 30,
		check = function() return true, "restored" end,
	},
	{
		-- closing the windows the mod wrapped, then opening a new one (an engine crash once)
		name = "close_windows",
		act = function() api.gui.fireReactEvent("closeAllWindows", nil) end,
		wait = 30,
		check = function() return true, "closed" end,
	},
	{
		-- the game reaches the tool stack through a ref to the replacement (game.tl), whose api is the
		-- shown stack's (fallback.lua); with every window closed the default tool is on top
		name = "tool_stack_api",
		check = function()
			local game_react_globals = require("::/gui/main/game_react_globals.tl")
			local ok, tool = pcall(function() return game_react_globals.getDefaultToolStackApi().getActiveTool() end)
			local name = ok and tool and tool.name or tostring(tool)
			return ok and tool ~= nil, "active tool=" .. tostring(name)
		end,
	},
	{
		name = "catchment_overlay",
		act = function()
			-- the overlay shows while no tool draws its own (Statistics, Line Manager ...)
			api.gui.fireReactEvent("clearToolStack", nil)
			api.gui.fireReactEvent("closeAllWindows", nil)
			api.gui.fireReactEvent("uio.catchment", { person = true, cargo = true })
		end,
		wait = 60,
		shot = "catchment_overlay",
		check = function()
			local shown = visible("uio.catchment.person")
			return true, "toggle visible=" .. tostring(shown) .. " (see the overlay in the screenshot)"
		end,
	},
	{
		name = "catchment_overlay_off",
		act = function() api.gui.fireReactEvent("uio.catchment", { person = false, cargo = false }) end,
		wait = 10,
		check = function() return true, "off" end,
	},
	{
		name = "vehicle_tooltip_block",
		act = function(ctx)
			if ctx.card_vehicle then api.gui.fireReactEvent("uio.debug.vehicle_tooltip", ctx.card_vehicle) end
		end,
		wait = 60,
		shot = "vehicle_tooltip",
		check = function(ctx)
			if not ctx.card_vehicle then return true, "skipped: no vehicle" end
			local shown = visible("probe.vehicle_tooltip")
			return shown, "tooltip probe visible=" .. tostring(shown) .. " (see the vehicle lines log)"
		end,
	},
	{
		name = "vehicle_tooltip_closed",
		act = function() api.gui.fireReactEvent("uio.debug.vehicle_tooltip", nil) end,
		wait = 10,
		check = function() return true, "closed" end,
	},
	{
		name = "town_window_bottleneck",
		act = function(ctx)
			local towns = api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN)
			ctx.town = towns[1]
			if ctx.town then api.gui.fireReactEvent("selectEntity", { entity = ctx.town, stack = false }) end
		end,
		wait = 120,
		shot = "town_window",
		check = function(ctx)
			if not ctx.town then return true, "skipped: no town" end
			return visible("uio.town.bottleneck"), "bottleneck line visible=" .. tostring(visible("uio.town.bottleneck"))
		end,
	},
	{
		-- the installed section functions, driven like vehicle.tl does (a key no real card uses): open in
		-- one window, remembered by the next, closed there by Modify's "collapse all" (vehicle.tl:501)
		name = "sections_collapse_all",
		check = function()
			local content_card = require("::/gui/main/content_card.tl")
			local function window()
				local state = { value = {} }
				function state.old() return state.value end
				function state.set(_self, v) state.value = v end
				local update, is_expanded = content_card.makeContentCardsCollapsibleFunctions(state, true)
				return { update = update, is_expanded = is_expanded }
			end
			local key = "uio.testbench.section"
			local first = window()
			first.update(key, true)
			local second = window()
			local remembered = second.is_expanded(key)
			second.update("", false)
			local collapsed = not second.is_expanded(key)
			local next_window = window().is_expanded(key)
			window().update(key, false)
			return remembered and collapsed and next_window, "remembered=" .. tostring(remembered)
				.. " collapsed=" .. tostring(collapsed) .. " next window=" .. tostring(next_window)
		end,
	},
	{
		-- the industry with the most output, as players look at those first
		name = "industry_window_cards",
		act = function(ctx)
			-- an industry whose expansion is blocked (the red area), else the one with the most output
			local blocked = {}
			local script = api.engine.system.gameScriptSystem.getEntityForGameScript(
				"::/game_mechanics/industries/industries.gs")
			local game_script = script and api.engine.getComponent(script, api.type.ComponentType.GAME_SCRIPT)
			local failed = game_script and game_script.state_native:find("industryFailedExtensions")
			local best, best_output = nil, -1
			for _i, entity in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)) do
				local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
				local output = api.engine.util.stock.getCargoOutputPerYear(industry.stockList)
				if failed and failed:find(entity) ~= nil then output = output + 1e9 blocked[entity] = true end
				if output > best_output then best, best_output = entity, output end
			end
			ctx.industry_blocked = best ~= nil and blocked[best] == true
			ctx.industry = best
			if best then
				api.gui.fireReactEvent("closeAllWindows", nil)
				api.gui.fireReactEvent("selectEntity", { entity = best, stack = false })
				api.gui.fireReactEvent("uio.debug.industry", best)
			end
		end,
		wait = 90,
		shot = "industry_window",
		check = function(ctx)
			if not ctx.industry then return true, "skipped: no industry" end
			local shown = visible("uio.industry.development." .. tostring(ctx.industry))
			return shown, "development card visible=" .. tostring(shown) .. " (see the industry log lines)"
		end,
	},
	{
		name = "industry_blocked_area_hidden",
		act = function() api.gui.fireReactEvent("uio.industry.blocked_area", false) end,
		wait = 60,
		shot = "industry_blocked_area_hidden",
		check = function(ctx)
			return true, "blocked industry=" .. tostring(ctx.industry_blocked) .. " (compare the red area with the shot before)"
		end,
	},
	{
		name = "industry_blocked_area_shown",
		act = function() api.gui.fireReactEvent("uio.industry.blocked_area", true) end,
		wait = 30,
		check = function() return true, "shown again" end,
	},
	{
		name = "bulldozer_station_warning",
		act = function(ctx)
			local component = ctx.card_station
				and api.engine.getComponent(ctx.card_station, api.type.ComponentType.STATION_GROUP)
			local station = component and component.stations[1]
			if station then api.gui.fireReactEvent("uio.debug.bulldoze", station) end
		end,
		wait = 30,
		check = function() return true, "see the bulldozer warning log line" end,
	},
	{
		name = "line_manager_cargo_icons",
		act = function(ctx)
			api.gui.fireReactEvent("closeAllWindows", nil)
			ctx.cargo_line = busiest_line()
			api.gui.fireReactEvent("openVehicleManager", { openWithLineEntity = ctx.cargo_line })
		end,
		wait = 180, -- row info refreshes every 2 s
		shot = "line_manager_cargo_icons",
		check = function(ctx)
			if not ctx.cargo_line then return true, "skipped: no line" end
			local cargo_util = require("::/gui/main/cargo_util.tl")
			local ids = cargo_util.getSortedProducedCargoTypes(
				{ lineEntity = ctx.cargo_line, getTendency = true, showEmpty = true }, "CAPACITY", true, nil, true)
			local column = visible("uio.lvm.cargo." .. tostring(ctx.cargo_line))
			return column and #ids > 0, string.format("line %d cargo types=%d column visible=%s",
				ctx.cargo_line, #ids, tostring(column))
		end,
	},
	{
		name = "lvm_models_row",
		act = function(ctx)
			api.gui.fireReactEvent("clearToolStack", nil)
			api.gui.fireReactEvent("closeAllWindows", nil)
			ctx.models_line, ctx.models_why = model_row_line()
			if ctx.models_line then
				api.gui.fireReactEvent("openVehicleManager", { openWithLineEntity = ctx.models_line })
			end
		end,
		wait = 120,
		shot = "line_manager_models",
		check = function(ctx)
			if not ctx.models_line then return true, "skipped: no line with two models or a shared model" end
			local row = api.gui.byId.isVisibleRecursive("uio.lvm.models")
			return row, string.format("line %d (%s) model row visible=%s", ctx.models_line, ctx.models_why, tostring(row))
		end,
	},
	{
		-- clicking the first model button: exactly that model's vehicles end up selected
		name = "lvm_models_select",
		act = function(ctx)
			if ctx.models_line then api.gui.fireReactEvent("uio.debug.lvm_models", { action = "select", index = 1 }) end
		end,
		wait = 30,
		shot = "line_manager_models_selected",
		check = function(ctx)
			if not ctx.models_line then return true, "skipped: no model row" end
			return api.gui.byId.isVisibleRecursive("menu.management"),
				"see '[ui_overhaul] lvm models: select ... ok' (MISMATCH = wrong selection)"
		end,
	},
	{
		-- "In all lines": the model's vehicles from every line join the list, selected
		name = "lvm_models_pull",
		act = function(ctx)
			if ctx.models_line then api.gui.fireReactEvent("uio.debug.lvm_models", { action = "pull", index = 1 }) end
		end,
		wait = 60,
		shot = "line_manager_models_all_lines",
		check = function(ctx)
			if not ctx.models_line then return true, "skipped: no model row" end
			return api.gui.byId.isVisibleRecursive("menu.management"),
				"see '[ui_overhaul] lvm models: pull ... ok' (MISMATCH = wrong selection)"
		end,
	},
	{
		-- Replace keeps the vehicle id: one vehicle of the line's second model becomes its first model
		name = "lvm_models_replace",
		act = function(ctx)
			ctx.replaced, ctx.replaced_to = nil, nil
			if not ctx.models_line then return end
			local first, keys = {}, {} -- model key -> the line's first vehicle of it
			for _i, v in ipairs(line_vehicles(ctx.models_line)) do
				local key = model_key(v)
				if key and not first[key] then first[key], keys[#keys + 1] = v, key end
			end
			if #keys < 2 then return end
			local tv = api.engine.getComponent(first[keys[1]], api.type.ComponentType.TRANSPORT_VEHICLE)
			ctx.replaced, ctx.replaced_to = first[keys[2]], keys[1]
			api.cmd.sendCommand(api.cmd.makeVehicleReplaceCmd(ctx.replaced, tv.transportVehicleConfig))
		end,
		wait = 180, -- the model row re-reads the fleet every 2 s
		check = function(ctx)
			if not ctx.replaced then return true, "skipped: no line with two models" end
			local applied = model_key(ctx.replaced) == ctx.replaced_to
			return applied, string.format("vehicle %d replaced in place with model %s: %s", ctx.replaced,
				ctx.replaced_to, tostring(applied))
		end,
	},
	{
		name = "lvm_models_after_replace",
		act = function(ctx)
			if ctx.replaced then api.gui.fireReactEvent("uio.debug.lvm_models", { action = "verify" }) end
		end,
		wait = 10,
		shot = "line_manager_models_after_replace",
		check = function(ctx)
			if not ctx.replaced then return true, "skipped: nothing replaced" end
			return api.gui.byId.isVisibleRecursive("menu.management"),
				"see '[ui_overhaul] lvm models: verify ... ok' (STALE = the row still shows the old models)"
		end,
	},
	{
		name = "lvm_models_hidden_for_one_model",
		act = function(ctx)
			api.gui.fireReactEvent("closeVehicleManager", nil)
			ctx.single_line = single_model_line()
		end,
		wait = 30,
		check = function(ctx)
			if not ctx.single_line then return true, "skipped: no line with a model of its own" end
			api.gui.fireReactEvent("openVehicleManager", { openWithLineEntity = ctx.single_line })
			return true, "opened line " .. tostring(ctx.single_line)
		end,
	},
	{
		name = "lvm_models_hidden_shot",
		wait = 120,
		shot = "line_manager_one_model",
		check = function(ctx)
			if not ctx.single_line then return true, "skipped: no line with a model of its own" end
			local row = api.gui.byId.isVisibleRecursive("uio.lvm.models")
			return not row, "model row visible=" .. tostring(row) .. " (expect false)"
		end,
	},
	{
		name = "terminal_usage_buttons",
		act = function(ctx)
			api.gui.fireReactEvent("closeAllWindows", nil)
			ctx.terminal_line = busiest_line()
			if ctx.terminal_line then api.gui.fireReactEvent("uio.debug.terminals", ctx.terminal_line) end
		end,
		wait = 90,
		shot = "terminal_popover",
		check = function(ctx)
			if not ctx.terminal_line then return true, "skipped: no line" end
			local shown = visible("uio.terminals.usage.1")
			if EASY_TERMINALS then return not shown, "Easy Terminal Assignment's popover, ours visible=" .. tostring(shown) end
			return shown, "usage buttons of terminal 1 visible=" .. tostring(shown)
		end,
	},
	{
		name = "terminal_popover_closes",
		act = function() api.gui.fireReactEvent("uio.debug.terminals", nil) end,
		wait = 30,
		check = function()
			local shown = visible("uio.terminals.usage.1")
			return not shown, "popover closed=" .. tostring(not shown)
		end,
	},
	{
		-- Terminal Selector opens a popover named TerminalSelection with parameters of its own; the mod
		-- must leave it alone (the stand-in renders) instead of showing an empty popover.
		name = "foreign_terminal_popover_untouched",
		act = function(ctx)
			if ctx.terminal_line then api.gui.fireReactEvent("uio.debug.foreign_terminals", ctx.terminal_line) end
		end,
		wait = 60,
		check = function(ctx)
			if not ctx.terminal_line then return true, "skipped: no line" end
			local ours, stand_in = visible("uio.terminals.usage.1"), visible("probe.fake_terminals")
			local details = string.format("ours=%s stand-in=%s", tostring(ours), tostring(stand_in))
			-- Easy Terminal Assignment takes this popover over too (its own issue, not ours)
			if EASY_TERMINALS then return not ours, details .. " (Easy Terminal Assignment active)" end
			return stand_in and not ours, details
		end,
	},
	{
		name = "station_terminal_buttons",
		act = function(ctx)
			api.gui.fireReactEvent("uio.debug.foreign_terminals", nil)
			api.gui.fireReactEvent("closeAllWindows", nil)
			local component = ctx.terminal_line and api.engine.getComponent(ctx.terminal_line, api.type.ComponentType.LINE)
			ctx.terminal_station = component and component.stops[1].stationGroup
			if ctx.terminal_station then
				api.gui.fireReactEvent("selectEntity", { entity = ctx.terminal_station, stack = false })
			end
		end,
		wait = 90,
		shot = "station_terminal_buttons",
		check = function(ctx)
			if not ctx.terminal_station then return true, "skipped: no line" end
			local shown = visible("uio.terminals.station." .. tostring(ctx.terminal_line) .. ".0")
			if TERMINAL_SELECTOR then
				return not shown, "Terminal Selector's station window, ours visible=" .. tostring(shown)
			end
			return shown, "button of the line's first stop visible=" .. tostring(shown)
		end,
	},
	{
		name = "line_window_terminal_button",
		act = function(ctx)
			api.gui.fireReactEvent("closeAllWindows", nil)
			if ctx.terminal_line then
				api.gui.fireReactEvent("selectEntity", { entity = ctx.terminal_line, stack = false })
			end
		end,
		wait = 90,
		check = function(ctx)
			if not ctx.terminal_line then return true, "skipped: no line" end
			local shown = visible("uio.terminals.stops." .. tostring(ctx.terminal_line) .. ".0")
			return shown, "button of stop 1 visible=" .. tostring(shown)
		end,
	},
	{
		name = "terminal_button_popover",
		act = function(ctx)
			if ctx.terminal_line then api.gui.fireReactEvent("uio.debug.terminal_button", ctx.terminal_line) end
		end,
		wait = 60,
		shot = "terminal_button_popover",
		check = function(ctx)
			if not ctx.terminal_line then return true, "skipped: no line" end
			local shown = visible("uio.terminals.usage.1")
			if EASY_TERMINALS then return not shown, "Easy Terminal Assignment's popover, ours visible=" .. tostring(shown) end
			return shown, "usage buttons of terminal 1 visible=" .. tostring(shown)
		end,
	},
	{
		-- the rows of that popover carry the preferred / unreachable marks (screenshot for the look)
		name = "terminal_rows_marked",
		wait = 30,
		shot = "terminal_rows",
		check = function(ctx)
			if not ctx.terminal_line or EASY_TERMINALS then return true, "skipped" end
			local shown = visible("uio.terminals.row.1")
			return shown, "row of terminal 1 visible=" .. tostring(shown)
		end,
	},
	{
		name = "stops_reach",
		act = function(ctx)
			if ctx.terminal_line then api.gui.fireReactEvent("uio.debug.reach", ctx.terminal_line) end
		end,
		wait = 10,
		check = function(ctx)
			if not ctx.terminal_line then return true, "skipped: no line" end
			return true, "see the reach log lines"
		end,
	},
	{
		-- A real change through the buttons' parameters (on the savegame copy), undone by the next check.
		name = "terminal_change_add",
		act = function(ctx)
			api.gui.fireReactEvent("uio.debug.terminal_button", nil)
			if not ctx.terminal_line then return end
			ctx.free_station, ctx.free_terminal = free_terminal(ctx.terminal_line)
			ctx.alternatives_before = alternatives(ctx.terminal_line)
			if ctx.free_station then
				api.gui.fireReactEvent("uio.debug.terminal_change", {
					line = ctx.terminal_line, station = ctx.free_station, terminal = ctx.free_terminal, add = true,
				})
			end
		end,
		wait = 60,
		check = function(ctx)
			if not ctx.terminal_line then return true, "skipped: no line" end
			if not ctx.free_station then return true, "skipped: no free terminal at the first stop" end
			local after = alternatives(ctx.terminal_line)
			return after == ctx.alternatives_before + 1,
				string.format("alternatives %d -> %d", ctx.alternatives_before, after)
		end,
	},
	{
		name = "terminal_change_remove",
		act = function(ctx)
			if ctx.terminal_line and ctx.free_station then
				api.gui.fireReactEvent("uio.debug.terminal_change", {
					line = ctx.terminal_line, station = ctx.free_station, terminal = ctx.free_terminal, add = false,
				})
			end
		end,
		wait = 60,
		check = function(ctx)
			if not ctx.terminal_line or not ctx.free_station then return true, "skipped" end
			local after = alternatives(ctx.terminal_line)
			return after == ctx.alternatives_before, string.format("alternatives back to %d (expect %d)", after,
				ctx.alternatives_before)
		end,
	},
	-- Notification ridge grouping (gui/notifications.lua). The ridge's module lives in the GUI's Lua
	-- state and cannot be loaded here (its recipes would register twice), so the check groups a fresh
	-- read of the game's notifications with the same core module and logs the expected numbers; compare
	-- them with the ridge's own "[ui_overhaul] notification ridge: ..." lines. run.sh fails the run if
	-- the ridge fell back to the base one.
	{
		name = "notification_ridge_groups",
		wait = 60,
		shot = "notification_ridge",
		check = function()
			local groups = require("ui_overhaul_1::/ui_overhaul/core/notification_groups.lua")
			local notification_util = require("::/game_mechanics/notifications/notification_util.tl")
			local native = notification_util.externalGetNotificationsStateNative()
			if not native then return true, "skipped: no notification state" end
			local entries = native:find("notifications")
			local items = {}
			for _i, id in ipairs(notification_util.getHistoryFromNative(native)) do
				local native_entry = entries:find(id)
				if native_entry ~= nil and not native_entry:find("dismissed") then
					local entry = notification_util.getNotificationEntryFromNative(native, id)
					items[#items + 1] = { id = id, timestamp = entry.timestamp, notification = entry.notification }
				end
			end
			return true, string.format("game: %d notifications in %d groups (compare the ridge's log line)",
				#items, #groups.build(items))
		end,
	},
	{
		name = "finance_income_statement",
		act = function()
			api.gui.fireReactEvent("closeAllWindows", nil)
			api.gui.fireReactEvent("openFinanceWindow", "Finances")
			api.gui.fireReactEvent("uio.finances.view", "income")
			api.gui.fireReactEvent("uio.debug.finances", nil)
		end,
		wait = 90,
		shot = "finance_income",
		check = function()
			local shown = visible("uio.finances.views")
			return shown, "statement views visible=" .. tostring(shown) .. " (see the finances log line)"
		end,
	},
	{
		name = "finance_cash_flow",
		act = function() api.gui.fireReactEvent("uio.finances.view", "cashflow") end,
		wait = 60,
		shot = "finance_cash_flow",
		check = function() return visible("uio.finances.views"), "cash flow" end,
	},
	{
		name = "finance_balance_sheet",
		act = function() api.gui.fireReactEvent("uio.finances.view", "balance") end,
		wait = 60,
		shot = "finance_balance_sheet",
		check = function() return visible("uio.finances.views"), "balance sheet" end,
	},
	{
		name = "finance_details",
		act = function() api.gui.fireReactEvent("uio.finances.view", "details") end,
		wait = 60,
		check = function() return visible("uio.finances.views"), "the game's table" end,
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
		name = "sliders_window",
		act = function()
			api.gui.fireReactEvent("clearToolStack", nil)
			api.gui.fireReactEvent("uio.debug.sliders", true)
		end,
		wait = 60,
		shot = "sliders",
		check = function()
			local shown = visible("probe.slider.percent")
			return shown, "test slider visible=" .. tostring(shown) .. " (see the ticks in the screenshot)"
		end,
	},
	{
		name = "sliders_window_closed",
		act = function() api.gui.fireReactEvent("uio.debug.sliders", false) end,
		wait = 10,
		check = function() return true, "closed" end,
	},
	{
		name = "build_measurements",
		act = function() api.gui.fireReactEvent("uio.debug.measure", nil) end,
		wait = 10,
		check = function() return true, "see the measure log lines" end,
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
		name = "vehicle_store_newest_first",
		act = function(ctx)
			api.gui.fireReactEvent("clearToolStack", nil)
			local depots = api.engine.getEntitiesWithComponent(api.type.ComponentType.VEHICLE_DEPOT)
			for _i, depot in ipairs(depots) do
				local component = api.engine.getComponent(depot, api.type.ComponentType.VEHICLE_DEPOT)
				if component and component.carrier == api.type.enum.Carrier.ROAD then ctx.depot = depot break end
			end
			ctx.depot = ctx.depot or depots[1]
			if ctx.depot then
				api.gui.fireReactEvent("buyVehicles", { title = "Test", depot = ctx.depot, carrier = api.type.enum.Carrier.ROAD })
			end
		end,
		wait = 120,
		shot = "vehicle_store",
		check = function(ctx) return true, "depot=" .. tostring(ctx.depot) end,
	},
	{
		name = "action_add_vehicle",
		act = function(ctx)
			api.gui.fireReactEvent("clearToolStack", nil)
			api.gui.fireReactEvent("closeAllWindows", nil)
			ctx.line, ctx.before = busiest_line()
			if ctx.line then api.gui.fireReactEvent("uio.action", { name = "add_vehicle", entity = ctx.line }) end
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
			if ctx.vehicle then api.gui.fireReactEvent("uio.action", { name = "remove_vehicle", entity = ctx.line }) end
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
	{
		-- a mission protects the oldest vehicle (the event mission_sim.script.tl fires): the uio.action
		-- event must leave it alone
		name = "action_remove_protected_vehicle",
		act = function(ctx)
			ctx.line = ctx.line or busiest_line()
			ctx.protected = ctx.line and oldest_vehicle(ctx.line)
			if not (ctx.protected and kept(ctx.protected)) then ctx.protected = nil return end
			api.gui.fireReactEvent("setProtectedEntities", { [ctx.protected] = true })
			api.gui.fireReactEvent("uio.action", { name = "remove_vehicle", entity = ctx.line })
		end,
		wait = 120,
		check = function(ctx)
			if not ctx.protected then return true, "skipped: no line with a vehicle in service" end
			api.gui.fireReactEvent("setProtectedEntities", {})
			local ok = kept(ctx.protected)
			return ok, string.format("vehicle %d kept=%s (log: \"Vehicle cannot be sold at this time.\")",
				ctx.protected, tostring(ok))
		end,
	},
	{
		-- the line window's Remove Vehicle on a protected vehicle: kept, and the reason under the buttons
		name = "line_window_protected_vehicle",
		act = function(ctx)
			api.gui.fireReactEvent("closeAllWindows", nil)
			ctx.protected = ctx.line and oldest_vehicle(ctx.line)
			if not (ctx.protected and kept(ctx.protected)) then ctx.protected = nil return end
			api.gui.fireReactEvent("selectEntity", { entity = ctx.line, stack = false })
			api.gui.fireReactEvent("setProtectedEntities", { [ctx.protected] = true })
		end,
		wait = 90,
		check = function(ctx)
			if not ctx.protected then return true, "skipped: no line with a vehicle in service" end
			return stops_card(ctx.line), "line window open=" .. tostring(stops_card(ctx.line))
		end,
	},
	{
		name = "line_window_remove_protected_feedback",
		act = function(ctx)
			if ctx.protected then
				api.gui.fireReactEvent("uio.debug.line_vehicles", { line = ctx.line, action = "remove" })
			end
		end,
		wait = 30,
		shot = "line_window_protected_feedback",
		check = function(ctx)
			if not ctx.protected then return true, "skipped: no line with a vehicle in service" end
			api.gui.fireReactEvent("setProtectedEntities", {})
			local ok = kept(ctx.protected)
			return ok, string.format("vehicle %d kept=%s (screenshot: \"Vehicle cannot be sold at this time.\" "
				.. "under the Vehicles card's buttons)", ctx.protected, tostring(ok))
		end,
	},
}

-- run.sh --only <name>: just those checks, after the fixture facts.
if fixture.only and #fixture.only > 0 then
	local wanted = { gui_fixture_facts = true }
	for _i, name in ipairs(fixture.only) do wanted[name] = true end
	local selected = {}
	for _i, check in ipairs(checks) do
		if wanted[check.name] then selected[#selected + 1] = check end
	end
	checks = selected
end

-- Crash probe (gui/probe.script.lua): set PROBE = true to open its window variants first.
local PROBE = false
if PROBE then
	local probes = {}
	for variant = 1, 5 do
		probes[#probes + 1] = {
			name = "probe_variant_" .. variant,
			act = function() api.gui.fireReactEvent("uio.probe", variant) end,
			wait = 120,
			check = function() return api.gui.byId.isVisibleRecursive("probe.window"), "window visible" end,
		}
	end
	for _i, check in ipairs(checks) do probes[#probes + 1] = check end
	return probes
end

return checks
