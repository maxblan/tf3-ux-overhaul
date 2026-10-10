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

-- Where UI Overhaul and another mod change the same part, the one that comes first in the mod list
-- wins (gui/priority.lua). The position of a mod, read the way priority.lua reads it: its smallest
-- generic resource id (ids follow the activation order); nil when it is not active.
---@param mod string
---@return integer?
local function position(mod)
	local types = { "react-replacement-config" }
	for _i, point in ipairs({ "ModEntryPointExtension", "LineEowExtensionPoint", "IndustryEowExtensionPoint",
		"MainModButtonAreaExtension", "StationGroupEowExtensionPoint", "VehicleEowExtensionPoint",
		"GameBarInfoDisplayExtension" }) do
		types[#types + 1] = "react-plugin ::" .. point
	end
	local best ---@type integer?
	for _i, type_name in ipairs(types) do
		for _j, id in ipairs(api.res.genericRep.getAllOfType(type_name)) do
			if api.res.genericRep.getName(id):sub(1, #mod + 2) == mod .. "::" and (best == nil or id < best) then
				best = id
			end
		end
	end
	return best
end

--- Whether `mod` is active and comes before UI Overhaul in the mod list: then it wins the part both change.
---@param mod string
---@return boolean
local function wins(mod)
	local theirs, ours = position(mod), position("ui_overhaul_1")
	return theirs ~= nil and ours ~= nil and theirs < ours
end

--- Whether feature `key` of the mod is switched off in its settings for this run (run.sh --off): that
-- part is expected vanilla.
---@param key string
---@return boolean
local function off(key)
	for _i, feature in ipairs(fixture.off or {}) do
		if feature == key then return true end
	end
	return false
end
local TERMINALS_OFF = off("terminals")
local STATION_TERMINALS_OFF = off("station_terminals")

-- Replaces the station window and brings its own terminal buttons there.
local TERMINAL_SELECTOR = wins("terminal_selector")
-- Takes over every popover named TerminalSelection.
local EASY_TERMINALS = wins("zhenya_easy_terminal_assignment")
-- Replaces the Finances table with statements of its own.
local FINANCIAL_STATEMENTS = wins("tcoleman_financial_statements_1")
-- Development and lines cards in the industry window.
local INDUSTRY_ENHANCED = wins("cayde_industry_enhanced_1")
-- Replaces the vehicle window (a top bar with its own minimize to a bar at the screen's edge).
local CLEAN_VEHICLE_VIEW = position("cayde_vue_vehicule_1") ~= nil
-- A window of its own, docked next to the Line Manager, opened from the mod buttons at the top left.
local SUPPLY_CHAIN_MANAGER = position("dgbooth_supply_chain_manager_1") ~= nil

---@param id string
---@return boolean
local function visible(id)
	return api.gui.byId.isVisibleRecursive(id)
end

---@param line Engine.Entity
---@return Engine.Entity[]
local function line_vehicles(line)
	return api.engine.system.transportVehicleSystem.getLineVehicles(line)
end

--- A road vehicle of the player's that is on its line, for the hover scene: the cursor is aimed
-- 1.5 m above the terrain, which at sea is the seabed, so a ship would be missed. Nil if none.
---@return Engine.Entity?
local function road_vehicle_en_route()
	local states = api.type.enum.TransportVehicleState
	for _i, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		for _j, vehicle in ipairs(line_vehicles(line)) do
			local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
			if tv and tv.carrier == api.type.enum.Carrier.ROAD and tv.state == states.EN_ROUTE then return vehicle end
		end
	end
	return nil
end

--- The player's line with the most vehicles, or nil.
---@return Engine.Entity? line
---@return integer vehicles
local function busiest_line()
	local best, best_count = nil, 0 ---@type Engine.Entity?, integer
	for _i, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		local count = #line_vehicles(line)
		if count > best_count then best, best_count = line, count end
	end
	return best, best_count
end

--- An industry that a stop of one of the player's lines reaches (the Served by card lists that line),
-- or nil.
---@return Engine.Entity?
local function served_industry()
	for _i, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
		for _j, stop in ipairs(component and component.stops or {}) do
			local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
			local station = group and group.stations[stop.station + 1]
			for _k, catchable in ipairs(station and api.engine.system.catchmentAreaSystem.getStationCatchables(station, true)
				or {}) do
				if api.engine.getComponent(catchable, api.type.ComponentType.INDUSTRY) then return catchable end
			end
		end
	end
	return nil
end

--- Every vehicle of the player's lines.
---@return Engine.Entity[]
local function all_line_vehicles()
	local result = {} ---@type Engine.Entity[]
	for _i, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		for _j, vehicle in ipairs(line_vehicles(line)) do result[#result + 1] = vehicle end
	end
	return result
end

---@param line Engine.Entity?
---@return boolean?
local function stops_card(line)
	return line and visible("uio.card.line.stops." .. tostring(line))
end

--- A terminal of the first stop's station group that is neither preferred nor alternative: station
-- and terminal (1-based), or nil.
---@param line Engine.Entity
---@return integer? station
---@return integer? terminal
local function free_terminal(line)
	local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
	local stop = component and component.stops[1]
	if not stop then return nil end -- not a line (any more), or no stops
	local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
	---@cast group -nil -- a line stop's station group always has this component
	for s, station_entity in ipairs(group.stations) do
		local station = api.engine.getComponent(station_entity, api.type.ComponentType.STATION)
		---@cast station -nil -- the stations of a station group have this component
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
---@param line Engine.Entity
---@return integer
local function alternatives(line)
	return #api.engine.getComponent(line, api.type.ComponentType.LINE).stops[1].alternativeTerminals
end

--- Any player line other than `line`.
---@param line Engine.Entity?
---@return Engine.Entity?
local function other_line(line)
	for _i, candidate in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		if candidate ~= line then return candidate end
	end
end

--- Composition key of a vehicle, as lvm_models.model_key builds it.
---@param vehicle Engine.Entity
---@return string?
local function model_key(vehicle)
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	if not tv then return nil end
	local counts, order = {}, {} ---@type table<integer, integer>, integer[] model id -> parts; model ids
	for _i, part in ipairs(tv.transportVehicleConfig.vehicles) do
		local id = part.part.modelId
		if not counts[id] then order[#order + 1] = id end
		counts[id] = (counts[id] or 0) + 1
	end
	table.sort(order)
	local parts = {} ---@type string[]
	for i, id in ipairs(order) do parts[i] = id .. "x" .. counts[id] end
	return table.concat(parts, ",")
end

--- A player line whose list shows the model row: two or more models on the line, or a model that
-- another line uses too. Returns the line and a description, or nil.
---@return Engine.Entity? line
---@return string? why
local function model_row_line()
	local lines = api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
	local key_lines = {} ---@type table<string, integer> key -> number of lines using it
	local line_keys = {} ---@type table<Engine.Entity, { keys: table<string, true>, count: integer }>
	for _i, line in ipairs(lines) do
		local keys, count = {}, 0 ---@type table<string, true>, integer
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
---@return Engine.Entity?
local function single_model_line()
	local lines = api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
	local key_lines, line_key = {}, {} ---@type table<string, integer>, table<Engine.Entity, string>
	for _i, line in ipairs(lines) do
		local keys, count, last = {}, 0, nil ---@type table<string, true>, integer, string?
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

---@param line Engine.Entity
---@return Engine.Entity?
local function oldest_vehicle(line)
	local best ---@type Engine.Entity?
	local best_time ---@type number
	for _i, vehicle in ipairs(line_vehicles(line)) do
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
		---@cast tv -nil -- the line's vehicles, read this frame
		local t = math.huge
		for _j, part in ipairs(tv.transportVehicleConfig.vehicles) do
			if part.purchaseTime < t then t = part.purchaseTime end -- not math.min: LuaLS cannot type it here
		end
		if best == nil or t < best_time then best, best_time = vehicle, t end
	end
	return best
end

--- The vehicle is still there and not on its way to be sold.
---@param vehicle Engine.Entity
---@return boolean
local function kept(vehicle)
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	return tv ~= nil and tv.sellOnArrival ~= true
end

--- What the checks keep between act and check, in the GUI state: serialisable values only.
---@class uo.testbench.GuiContext
---@field card_line? Engine.Entity
---@field card_station? Engine.Entity a station group
---@field card_vehicle? Engine.Entity
---@field hover_vehicle? Engine.Entity the vehicle the gallery hovers (a road vehicle where there is one)
---@field second_line? Engine.Entity
---@field cargo_line? Engine.Entity
---@field clone_before? integer
---@field town? Engine.Entity
---@field industry? Engine.Entity
---@field screen? { x: integer, y: integer } screen size in pixels
---@field industry_blocked? boolean
---@field models_line? Engine.Entity
---@field models_why? string
---@field replaced? Engine.Entity
---@field replaced_to? string a model key
---@field single_line? Engine.Entity
---@field terminal_line? Engine.Entity
---@field terminal_station? Engine.Entity a station group
---@field free_station? integer 1-based
---@field free_terminal? integer 1-based
---@field alternatives_before? integer
---@field configure? Engine.Entity a construction
---@field depot? Engine.Entity
---@field line? Engine.Entity
---@field before? integer the line's vehicles before the action
---@field vehicle? Engine.Entity
---@field public protected? Engine.Entity a protected vehicle; `public` since the name is also a keyword
---@field spot_x? number the gallery's free land for the track tool
---@field spot_y? number
---@field header_vehicle? Engine.Entity the vehicle whose window the title row checks use
---@field search_vehicles? Engine.Entity[] the vehicles the vehicle search checks list
---@field served_industry? Engine.Entity an industry a line reaches

---@class uo.testbench.GuiCheck
---@field name string unique, shown in the PASS/FAIL line
---@field act? fun(ctx: uo.testbench.GuiContext) drives the GUI
---@field wait? integer guiUpdate calls between act and check
---@field shot? string screenshot name: run.sh captures the screen after the check
---@field check fun(ctx: uo.testbench.GuiContext): boolean?, string passed, and details

--- Whether the screen is the one the fixed mouse positions of some checks were taken on (3440 x 1440):
-- elsewhere they would point at something else, and those checks pass as skipped.
---@return boolean
local function reference_screen()
	local screen = api.gui.camera.getSize()
	return screen.x == 3440 and math.abs(screen.y - 1440) <= 1
end

--- Asks run.sh to move the mouse to screen pixel `x`, `y` (and to click there with `click`): hovers,
-- real clicks and the track tool's first point cannot be driven otherwise. run.sh does it in log
-- order, before the next SHOT, and leaves the cursor there for that shot.
---@param x number
---@param y number
---@param click? boolean
local function mouse(x, y, click)
	debugPrint(string.format("[testbench] %s %d %d", click and "CLICK" or "MOUSE", math.floor(x + 0.5),
		math.floor(y + 0.5)))
end

---@type uo.testbench.GuiCheck[]
local checks = {
	{
		name = "gui_fixture_facts",
		-- the mod logs its features and which mod won where both change the same part
		act = function() api.gui.fireReactEvent("uio.debug.priority", nil) end,
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
		-- with Supply Chain Manager: its window, opened by its mod button (the third at the top left on a
		-- 3440 x 1440 screen, seen in a shot), next to the Line Manager
		name = "supply_chain_manager_window",
		act = function()
			if SUPPLY_CHAIN_MANAGER and reference_screen() then mouse(176, 42, true) end
		end,
		wait = 240,
		shot = "supply_chain_manager_window",
		check = function()
			if not (SUPPLY_CHAIN_MANAGER and reference_screen()) then return true, "skipped" end
			local shown = visible("dgbooth_supply_chain_manager_window_1")
			return shown, "window visible=" .. tostring(shown)
		end,
	},
	{
		-- with Supply Chain Manager: its "add to the plan" button next to Locate in a Line Manager row, shown
		-- while the mouse is over the row (the first line row; the Line Manager starts lower with this mod's
		-- title row, 3440 x 1440 screen)
		name = "supply_chain_manager_row",
		act = function()
			if SUPPLY_CHAIN_MANAGER and reference_screen() then
				mouse(280, position("ui_overhaul_1") and 292 or 228)
			end
		end,
		wait = 120,
		shot = "supply_chain_manager_row",
		check = function()
			return true, (SUPPLY_CHAIN_MANAGER and reference_screen()) and "see the shot" or "skipped"
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
		-- the Line Manager (no title bar) has a title row of its own with the minimize button; folded,
		-- only that row stays
		name = "line_manager_minimize",
		act = function() api.gui.fireReactEvent("uio.debug.minimize_all", nil) end,
		wait = 30,
		shot = "line_manager_minimized",
		check = function()
			local window, content = visible("menu.management"), visible("uio.minimize.menu.management")
			return window and not content,
				string.format("window open=%s content visible=%s (expect true, false)", tostring(window), tostring(content))
		end,
	},
	{
		name = "line_manager_restore",
		act = function() api.gui.fireReactEvent("uio.debug.minimize_all", nil) end,
		wait = 30,
		shot = "line_manager_restored",
		check = function()
			local content = visible("uio.minimize.menu.management")
			return content, "content visible=" .. tostring(content)
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
			local id = "temp.view.entity_" .. tostring(ctx.card_vehicle)
			local window, content = visible(id), visible("uio.minimize." .. id)
			return window and not content,
				string.format("window open=%s content visible=%s (expect true, false)", tostring(window), tostring(content))
		end,
	},
	{
		name = "entity_window_restore",
		act = function() api.gui.fireReactEvent("uio.debug.minimize_all", nil) end,
		wait = 30,
		check = function() return true, "restored" end,
	},
	{
		-- the Line Manager in two columns: twice as wide, with the lines and stops left and the vehicles
		-- right (see the shot); the window's width as a part of the screen in the log
		name = "line_manager_columns",
		act = function(ctx)
			api.gui.fireReactEvent("closeAllWindows", nil)
			ctx.card_line = ctx.card_line or busiest_line()
			api.gui.fireReactEvent("openVehicleManager", { openWithLineEntity = ctx.card_line })
		end,
		wait = 120,
		shot = "line_manager_columns",
		check = function()
			local size = api.gui.byId.getSize("menu.management")
			local shown = visible("menu.management")
			debugPrint(string.format("[testbench] Line Manager size %.3f x %.3f (parts of the screen)", size.x, size.y))
			-- the game's Line Manager is about 0.15 of a 3440 wide screen: in columns it is about twice that
			return shown, string.format("line manager visible=%s width=%.3f height=%.3f (columns off: about half as wide)",
				tostring(shown), size.x, size.y)
		end,
	},
	{
		-- the stop's cargo filter (Load card), for the Fill Level slider: it stretches across the row like
		-- the game's, while the wait-time sliders keep their width (sliders.css.lua)
		name = "cargo_filter_window",
		act = function(ctx) api.gui.fireReactEvent("uio.debug.cargo_filter", ctx.card_line) end,
		wait = 60,
		shot = "cargo_filter_window",
		check = function() return true, "see the shot and the cargo filter log line" end,
	},
	{
		-- a click on the stop's first cargo filter (World#1's passenger filter, 3440 x 1440 screen, seen in
		-- the shot above) edits it: the Fill Level row
		name = "cargo_filter_fill_level",
		act = function() if reference_screen() then mouse(1467, 745, true) end end,
		wait = 60,
		shot = "cargo_filter_fill_level",
		check = function() return true, reference_screen() and "see the shot: Fill Level spans the row" or "skipped" end,
	},
	{
		-- the vehicle search: the list of all the player's vehicles, then a search for "Zug"
		name = "vehicle_search_list",
		act = function(ctx)
			ctx.search_vehicles = all_line_vehicles()
			api.gui.fireReactEvent("openVehicleManager", { openWithVehicleEntities = ctx.search_vehicles })
		end,
		wait = 90,
		shot = "vehicle_search_list",
		check = function()
			api.gui.fireReactEvent("uio.debug.vehicle_search", { log = true })
			-- the model row: its chips and "In all lines" side by side, as parts of the screen
			local row, pull = api.gui.byId.getSize("uio.lvm.models"), api.gui.byId.getSize("uio.lvm.models.pull")
			debugPrint(string.format("[testbench] model row %.4f wide, In all lines %.4f wide", row.x, pull.x))
			return visible("menu.management"), "see the vehicle search log line (all vehicles listed)"
		end,
	},
	{
		name = "vehicle_search_match",
		act = function() api.gui.fireReactEvent("uio.debug.vehicle_search", "Zug") end,
		wait = 30,
		shot = "vehicle_search_match",
		check = function()
			api.gui.fireReactEvent("uio.debug.vehicle_search", { log = true })
			local none = visible("uio.lvm.search.none")
			return not none, "no-match text visible=" .. tostring(none) .. " (expect false; rows in the log line)"
		end,
	},
	{
		name = "vehicle_search_none",
		act = function() api.gui.fireReactEvent("uio.debug.vehicle_search", "xyzzy") end,
		wait = 30,
		shot = "vehicle_search_none",
		check = function()
			api.gui.fireReactEvent("uio.debug.vehicle_search", { log = true })
			local none = visible("uio.lvm.search.none")
			return none, "no-match text visible=" .. tostring(none) .. " (expect true)"
		end,
	},
	{
		name = "vehicle_search_cleared",
		act = function() api.gui.fireReactEvent("uio.debug.vehicle_search", "") end,
		wait = 30,
		check = function()
			api.gui.fireReactEvent("uio.debug.vehicle_search", { log = true })
			local none = visible("uio.lvm.search.none")
			return not none, "no-match text visible=" .. tostring(none) .. " (expect false; all vehicles back in the log)"
		end,
	},
	{
		-- the Served by card: each line with its cargo and its rate (see the shot)
		name = "industry_served_rates",
		act = function(ctx)
			api.gui.fireReactEvent("closeAllWindows", nil)
			ctx.served_industry = served_industry()
			if ctx.served_industry then
				api.gui.fireReactEvent("selectEntity", { entity = ctx.served_industry, stack = false })
			end
		end,
		wait = 150,
		shot = "industry_served_rates",
		check = function(ctx)
			if not ctx.served_industry then return true, "skipped: no industry within reach of a line" end
			local shown = visible("temp.view.entity_" .. tostring(ctx.served_industry))
			return shown, "industry window open=" .. tostring(shown) .. " (see the Served by card in the shot)"
		end,
	},
	{
		-- the vehicle window's title row: a click on the rename button, aimed from outside the window,
		-- renames (reported: the minimize button took it, as the row moved left when the engine showed
		-- its pin button). Before the vehicle actions: a vehicle they sell can crash the game when it
		-- reaches the depot (the game's own fault, see docs/api_cookbook.md), so nothing runs long after them.
		name = "title_row_park_mouse",
		act = function()
			api.gui.fireReactEvent("closeAllWindows", nil)
			-- the mouse off the window to come (entity windows open at the right edge): the engine shows
			-- the pin button once the mouse is over the window, and the click comes from outside
			mouse(20, api.gui.camera.getSize().y / 2)
		end,
		wait = 180,
		check = function() return true, "mouse parked" end,
	},
	{
		name = "title_row_buttons",
		act = function(ctx)
			local line = busiest_line()
			ctx.header_vehicle = line and oldest_vehicle(line)
			if ctx.header_vehicle then
				api.gui.fireReactEvent("selectEntity", { entity = ctx.header_vehicle, stack = false })
			end
		end,
		wait = 120,
		shot = "title_row",
		check = function(ctx)
			if not ctx.header_vehicle then return true, "skipped: no vehicle" end
			return true, "vehicle window opened"
		end,
	},
	{
		-- a real click on the rename button's centre (minimize.lua logs the buttons' pixels, "[ui_overhaul]
		-- title row ...", and asks run.sh for the click): the title becomes a text field (the log line
		-- after the click says editing=true) and the window stays unfolded
		name = "title_row_rename_click",
		act = function(ctx)
			if ctx.header_vehicle then api.gui.fireReactEvent("uio.debug.header", { click = "rename" }) end
		end,
		wait = 300,
		shot = "title_row_after_rename_click",
		check = function(ctx)
			if not ctx.header_vehicle then return true, "skipped: no vehicle" end
			local id = "temp.view.entity_" .. tostring(ctx.header_vehicle)
			local window, content = visible(id), visible("uio.minimize." .. id)
			return window and content, string.format("window open=%s content visible=%s (expect true, true; "
				.. "editing in the title row log line)", tostring(window), tostring(content))
		end,
	},
	{
		-- the title row's state after the click, in its log line
		name = "title_row_state",
		act = function() api.gui.fireReactEvent("uio.debug.header", nil) end,
		wait = 10,
		check = function() return true, "logged" end,
	},
	{
		-- a long name (in the savegame copy): the title is cut short with the buttons in the window,
		-- not widening it (see the shot and the title row log line)
		name = "title_row_long_name",
		act = function(ctx)
			api.gui.fireReactEvent("closeAllWindows", nil)
			if ctx.header_vehicle then
				api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(ctx.header_vehicle,
					"Interregio Express Bodensee - Oberschwaben - Allgaeu - Muenchen Hauptbahnhof"))
				api.gui.fireReactEvent("selectEntity", { entity = ctx.header_vehicle, stack = false })
			end
		end,
		wait = 120,
		shot = "title_row_long_name",
		check = function(ctx)
			if not ctx.header_vehicle then return true, "skipped: no vehicle" end
			api.gui.fireReactEvent("uio.debug.header", nil)
			return visible("temp.view.entity_" .. tostring(ctx.header_vehicle)), "window open"
		end,
	},
	{
		name = "title_row_close",
		act = function() api.gui.fireReactEvent("closeAllWindows", nil) end,
		wait = 30,
		check = function() return true, "closed" end,
	},
	{
		-- with Clean Vehicle View: its minimize (">" in its top bar) closes the vehicle window and opens
		-- its bar at the screen's edge, a window of its own; then the vehicle window again
		name = "clean_vehicle_view_minimize",
		act = function(ctx)
			ctx.header_vehicle = nil
			if not (CLEAN_VEHICLE_VIEW and reference_screen()) then return end
			local line = busiest_line()
			ctx.header_vehicle = line and oldest_vehicle(line)
			if ctx.header_vehicle then
				api.gui.fireReactEvent("selectEntity", { entity = ctx.header_vehicle, stack = false })
				-- the ">" button, with the vehicle window at the screen's right edge (seen in a shot)
				mouse(2830, 100, true)
			end
		end,
		wait = 300,
		shot = "clean_vehicle_view_minimized",
		check = function(ctx)
			if not ctx.header_vehicle then return true, "skipped" end
			local bar, window = visible("cayde.vue.mini"), visible("temp.view.entity_" .. tostring(ctx.header_vehicle))
			return bar and not window, string.format("bar=%s vehicle window=%s (expect true, false)",
				tostring(bar), tostring(window))
		end,
	},
	{
		name = "clean_vehicle_view_reopen",
		act = function(ctx)
			if ctx.header_vehicle then
				api.gui.fireReactEvent("selectEntity", { entity = ctx.header_vehicle, stack = false })
			end
		end,
		wait = 180,
		shot = "clean_vehicle_view_reopened",
		check = function(ctx)
			if not ctx.header_vehicle then return true, "skipped" end
			local shown = visible("temp.view.entity_" .. tostring(ctx.header_vehicle))
			api.gui.fireReactEvent("closeAllWindows", nil)
			return shown, "vehicle window open=" .. tostring(shown)
		end,
	},
	{
		-- the Finances window: the title row (title, rename, minimize before close) and, once folded, no
		-- more than its title bar although the game gives it a fixed size
		name = "finances_window_title_row",
		act = function() api.gui.fireReactEvent("openFinanceWindow", nil) end,
		wait = 60,
		shot = "finances_window",
		check = function()
			local open = visible("menu.finance.window")
			return open, "finances window visible=" .. tostring(open) .. " (see the title row in the screenshot)"
		end,
	},
	{
		name = "finances_window_minimize",
		act = function() api.gui.fireReactEvent("uio.debug.minimize_all", nil) end,
		wait = 30,
		shot = "finances_window_minimized",
		check = function()
			local open, content = visible("menu.finance.window"), visible("uio.minimize.menu.finance.window")
			return open and not content,
				string.format("window open=%s content visible=%s (expect true, false)", tostring(open), tostring(content))
		end,
	},
	{
		name = "finances_window_restore",
		act = function() api.gui.fireReactEvent("uio.debug.minimize_all", nil) end,
		wait = 30,
		shot = "finances_window_restored",
		check = function()
			local content = visible("uio.minimize.menu.finance.window")
			return content, "content visible=" .. tostring(content)
		end,
	},
	{
		-- closed again: the statement checks open it on another tab, which an open window keeps
		name = "finances_window_closed",
		act = function() api.gui.fireReactEvent("closeFinanceWindow", nil) end,
		wait = 30,
		check = function() return true, "closed" end,
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
		-- run in the UI's Lua state: the testbench's own would load react.lua again
		name = "tool_stack_api",
		act = function() api.gui.fireReactEvent("uio.debug.tool_stack", nil) end,
		wait = 10,
		check = function() return true, "see '[ui_overhaul] tool stack api: ... ok' (check failed = broken)" end,
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
		-- run in the UI's Lua state (entry.lua): the testbench's own would load react.lua again
		name = "sections_collapse_all",
		act = function() api.gui.fireReactEvent("uio.debug.sections", nil) end,
		wait = 10,
		check = function() return true, "see '[ui_overhaul] sections: ... ok' (check failed = broken)" end,
	},
	{
		-- the industry with the most output, as players look at those first
		name = "industry_window_cards",
		act = function(ctx)
			-- an industry whose expansion is blocked (the red area), else the one with the most output
			local blocked = {} ---@type table<Engine.Entity, true>
			local script = api.engine.system.gameScriptSystem.getEntityForGameScript(
				"::/game_mechanics/industries/industries.gs")
			local game_script = script and api.engine.getComponent(script, api.type.ComponentType.GAME_SCRIPT)
			-- the script keeps a table there (industries.d.tl); the base reads it the same way (industry.tl:62)
			local failed = game_script and game_script.state_native:find("industryFailedExtensions") --[[@as NativeLuaTable?]]
			local best, best_output = nil, -1 ---@type Engine.Entity?, number
			for _i, entity in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)) do
				local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
				---@cast industry -nil -- the entities with this component
				local output = api.engine.util.stock.getCargoOutputPerYear(industry.stockList) ---@type number
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
			if INDUSTRY_ENHANCED then return not shown, "Industry UI Enhanced comes first, ours visible=" .. tostring(shown) end
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
			-- model key -> the line's first vehicle of it; the keys in order
			local first, keys = {}, {} ---@type table<string, Engine.Entity>, string[]
			for _i, v in ipairs(line_vehicles(ctx.models_line)) do
				local key = model_key(v)
				if key and not first[key] then first[key], keys[#keys + 1] = v, key end
			end
			if #keys < 2 then return end
			local tv = api.engine.getComponent(first[keys[1]], api.type.ComponentType.TRANSPORT_VEHICLE)
			---@cast tv -nil -- model_key read it a moment ago
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
			if TERMINALS_OFF then
				return not shown, "Select Terminals off: the base popover, ours visible=" .. tostring(shown)
			end
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
			if STATION_TERMINALS_OFF then return not shown, "station window buttons off, ours visible=" .. tostring(shown) end
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
			-- the log line "[ui_overhaul] terminal popover: the game's own" and the shot show the base one
			if TERMINALS_OFF then
				return not shown, "Select Terminals off: the base popover, ours visible=" .. tostring(shown)
			end
			return shown, "usage buttons of terminal 1 visible=" .. tostring(shown)
		end,
	},
	{
		-- the rows of that popover carry the preferred / unreachable marks (screenshot for the look)
		name = "terminal_rows_marked",
		wait = 30,
		shot = "terminal_rows",
		check = function(ctx)
			if not ctx.terminal_line or EASY_TERMINALS or TERMINALS_OFF then return true, "skipped" end
			local shown = visible("uio.terminals.row.1")
			return shown, "row of terminal 1 visible=" .. tostring(shown)
		end,
	},
	{
		-- opened at the screen's bottom right corner, as from a stop button near the edge on a wide screen:
		-- the popover moves onto the screen (see "[ui_overhaul] terminal popover moved onto the screen" and
		-- "[ui_overhaul] terminal popover now at content ...: on the screen"; this check sees only that it shows)
		name = "terminal_popover_on_screen",
		act = function(ctx)
			local screen = api.gui.camera.getSize()
			ctx.screen = { x = screen.x, y = screen.y }
			if ctx.terminal_line then
				-- positions are parts of the screen (0..1), as a button's getPosition gives them
				api.gui.fireReactEvent("uio.debug.terminal_button", { line = ctx.terminal_line, x = 0.97, y = 0.9 })
			end
		end,
		wait = 60,
		shot = "terminal_popover_on_screen",
		check = function(ctx)
			if not ctx.terminal_line or EASY_TERMINALS or TERMINALS_OFF then return true, "skipped" end
			local shown = visible("uio.terminals.usage.1")
			local screen = ctx.screen or { x = 0, y = 0 }
			return shown, string.format("screen %dx%d, popover visible=%s (see the placement log line and the shot)",
				screen.x, screen.y, tostring(shown))
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
			-- tables in the native state; the base casts them the same way (notification_popups.tl:253-255)
			local entries = native:find("notifications") --[[@as NativeLuaTable]]
			local items = {} ---@type uo.core.notification_groups.Item[]
			for _i, id in ipairs(notification_util.getHistoryFromNative(native)) do
				local native_entry = entries:find(id) --[[@as NativeLuaTable?]]
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
			if FINANCIAL_STATEMENTS then return not shown, "Real Financial Statements comes first, ours=" .. tostring(shown) end
			return shown, "statement views visible=" .. tostring(shown) .. " (see the finances log line)"
		end,
	},
	{
		name = "finance_details",
		act = function() api.gui.fireReactEvent("uio.finances.view", "details") end,
		wait = 60,
		check = function() return visible("uio.finances.views") ~= FINANCIAL_STATEMENTS, "the game's table" end,
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
			return shown, "test slider visible=" .. tostring(shown)
		end,
	},
	{
		name = "sliders_window_closed",
		act = function() api.gui.fireReactEvent("uio.debug.sliders", false) end,
		wait = 10,
		check = function() return true, "closed" end,
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
	local wanted = { gui_fixture_facts = true } ---@type table<string, true>
	for _i, name in ipairs(fixture.only) do wanted[name] = true end
	local selected = {} ---@type uo.testbench.GuiCheck[]
	for _i, check in ipairs(checks) do
		if wanted[check.name] then selected[#selected + 1] = check end
	end
	checks = selected
end

-- Gallery (run.sh --gallery): scenes for the mod.io gallery instead of the checks, each a "SHOT
-- gallery_<name>" for tools/gallery. The game is paused, so the same scene looks the same in the run
-- with the mod and in the one without it (run.sh --vanilla), which only takes the scenes marked
-- `pair`; they drive the game's own events only. Scenes of the mod alone use its debug events.

--- A player line with a stop its vehicles cannot reach (the station window's alert), and that stop's
-- station group; else the busiest line and its first stop. The problems come per entry of the line's
-- path (stops and waypoints); a missing path belongs to the next stop (line_problems.stop_problems).
---@return Engine.Entity? line
---@return Engine.Entity? station_group
local function problem_stop()
	local failures, empty = 0, 0
	for _i, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
		local ok, segments = pcall(api.engine.util.line.getDetailedLineProblems, line)
		if not ok then
			failures = failures + 1
			if failures == 1 then debugPrint("[testbench] gallery: line problems failed: ", tostring(segments)) end
		elseif #segments == 0 then
			empty = empty + 1
		end
		if component and ok then
			local flat = {} ---@type (Engine.Entity|false)[] station group per path entry; false for a waypoint
			for _j, stop in ipairs(component.stops) do
				flat[#flat + 1] = stop.stationGroup
				for _k in ipairs(stop.waypoints) do flat[#flat + 1] = false end
			end
			for index, segment in ipairs(segments) do
				for _j, state in ipairs(segment) do
					if state.noPath or state.noPathFromAlternative or state.noPathToAlternative then
						for step = 1, #flat do
							local group = flat[(index + step - 1) % #flat + 1]
							if group then return line, group end
						end
					end
				end
			end
		end
	end
	debugPrint("[testbench] gallery: no line problem found (", failures, " reads failed, ", empty, " empty)")
	local line = busiest_line()
	local component = line and api.engine.getComponent(line, api.type.ComponentType.LINE)
	return line, component and component.stops[1] and component.stops[1].stationGroup
end

--- An industry whose expansion is blocked (the red area), else the one with the most output.
---@return Engine.Entity?
local function blocked_industry()
	local script = api.engine.system.gameScriptSystem.getEntityForGameScript("::/game_mechanics/industries/industries.gs")
	local game_script = script and api.engine.getComponent(script, api.type.ComponentType.GAME_SCRIPT)
	local failed = game_script and game_script.state_native:find("industryFailedExtensions") --[[@as NativeLuaTable?]]
	local best, best_output = nil, -1 ---@type Engine.Entity?, number
	for _i, entity in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)) do
		local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
		---@cast industry -nil -- the entities with this component
		local output = api.engine.util.stock.getCargoOutputPerYear(industry.stockList) ---@type number
		if failed and failed:find(entity) ~= nil then output = output + 1e9 end
		if output > best_output then best, best_output = entity, output end
	end
	return best
end


--- The screen pixel of world point `x`, `y` on the ground (plus `up` metres).
---@param x number
---@param y number
---@param up? number
---@return number x
---@return number y
local function screen_of(x, y, up)
	local ground = api.engine.terrain.getHeightAt(api.type.Vec2f.new(x, y))
	local p = api.gui.camera.world2Screen(api.type.Vec3f.new(x, y, ground + (up or 0)))
	return p.x, p.y
end

local function clear()
	-- the tool windows stay open side by side (tool_stack.lua): closed one by one
	for _i, event in ipairs({ "closeVehicleManager", "closeStatisticsWindow", "closeFinanceWindow" }) do
		api.gui.fireReactEvent(event, nil)
	end
	api.gui.fireReactEvent("clearToolStack", nil)
	api.gui.fireReactEvent("closeAllWindows", nil)
end

---@class uo.testbench.GalleryScene: uo.testbench.GuiCheck
---@field pair? boolean also shot without the mod, for a before/after image

---@type uo.testbench.GalleryScene[]
local scenes = {
	{
		-- the line problems exist once the simulation ran a moment
		name = "gallery_warm_up",
		pair = true,
		wait = 300,
		check = function() return true, "warmed up" end,
	},
	{
		name = "gallery_start",
		pair = true,
		act = function(ctx)
			api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(0)) -- paused: both runs show the same scene
			clear()
			ctx.card_line = busiest_line()
			ctx.models_line = model_row_line()
			ctx.terminal_line, ctx.terminal_station = problem_stop()
			ctx.industry = blocked_industry()
			ctx.card_vehicle = ctx.card_line and oldest_vehicle(ctx.card_line)
			if ctx.terminal_station then api.gui.camera.focusEntity(ctx.terminal_station) end
		end,
		wait = 240,
		check = function(ctx)
			return true, string.format("line=%s models line=%s problem line=%s station=%s industry=%s vehicle=%s",
				tostring(ctx.card_line), tostring(ctx.models_line), tostring(ctx.terminal_line),
				tostring(ctx.terminal_station), tostring(ctx.industry), tostring(ctx.card_vehicle))
		end,
	},
	{
		name = "gallery_line_manager",
		pair = true,
		act = function(ctx)
			clear()
			if ctx.models_line then api.gui.fireReactEvent("openVehicleManager", { openWithLineEntity = ctx.models_line }) end
		end,
		wait = 240, -- the row info refreshes every 2 s
		shot = "gallery_line_manager",
		check = function() return visible("menu.management"), "line manager" end,
	},
	{
		name = "gallery_models_select",
		act = function(ctx)
			if ctx.models_line then api.gui.fireReactEvent("uio.debug.lvm_models", { action = "select", index = 1 }) end
		end,
		wait = 60,
		shot = "gallery_models_select",
		check = function() return visible("uio.lvm.models"), "model row" end,
	},
	{
		name = "gallery_models_all_lines",
		act = function(ctx)
			if ctx.models_line then api.gui.fireReactEvent("uio.debug.lvm_models", { action = "pull", index = 1 }) end
		end,
		wait = 90,
		shot = "gallery_models_all_lines",
		-- every vehicle of the model is listed now, so the row has nothing left to pull and hides
		check = function() return visible("menu.management"), "pulled from all lines" end,
	},
	{
		name = "gallery_models_replace",
		act = function(ctx)
			local first = ctx.models_line and line_vehicles(ctx.models_line)[1]
			local key = first and model_key(first)
			local same = {} ---@type Engine.Entity[]
			for _i, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
				for _j, v in ipairs(line_vehicles(line)) do
					if key and model_key(v) == key then same[#same + 1] = v end
				end
			end
			-- asks only (the Line Manager's question): nothing is replaced
			if #same >= 2 then api.gui.fireReactEvent("uio.debug.replace", same) end
		end,
		wait = 60,
		shot = "gallery_models_replace",
		check = function() return visible("menu.management"), "replace question" end,
	},
	{
		name = "gallery_statistics",
		pair = true,
		act = function()
			clear()
			api.gui.fireReactEvent("openStatisticsWindow", "Line")
		end,
		wait = 120,
		shot = "gallery_statistics",
		check = function() return visible("menu.statistics.window"), "statistics" end,
	},
	{
		-- the quick filter once the window is there
		name = "gallery_statistics_losing",
		act = function() api.gui.fireReactEvent("uio.statistics.filter", "losing") end,
		wait = 90,
		shot = "gallery_statistics_losing",
		check = function() return visible("menu.statistics.window"), "statistics" end,
	},
	{
		name = "gallery_station",
		pair = true,
		act = function(ctx)
			api.gui.fireReactEvent("uio.statistics.filter", "all")
			clear()
			if ctx.terminal_station then
				api.gui.camera.focusEntity(ctx.terminal_station)
				api.gui.fireReactEvent("selectEntity", { entity = ctx.terminal_station, stack = false })
			end
		end,
		wait = 180,
		shot = "gallery_station",
		check = function(ctx) return ctx.terminal_station ~= nil, "station " .. tostring(ctx.terminal_station) end,
	},
	{
		name = "gallery_terminals",
		act = function(ctx)
			-- left of the station window, beside its rows (a click opens it at the button)
			if ctx.terminal_line then
				api.gui.fireReactEvent("uio.debug.terminal_button", { line = ctx.terminal_line, x = 0.25, y = 0.15 })
			end
		end,
		wait = 90,
		shot = "gallery_terminals",
		check = function() return visible("uio.terminals.usage.1"), "terminal popover" end,
	},
	{
		name = "gallery_industry",
		pair = true,
		act = function(ctx)
			api.gui.fireReactEvent("uio.debug.terminal_button", nil)
			clear()
			if ctx.industry then
				api.gui.camera.focusEntity(ctx.industry)
				api.gui.fireReactEvent("selectEntity", { entity = ctx.industry, stack = false })
			end
		end,
		wait = 240,
		shot = "gallery_industry",
		check = function(ctx) return ctx.industry ~= nil, "industry " .. tostring(ctx.industry) end,
	},
	{
		name = "gallery_finances",
		pair = true,
		act = function()
			clear()
			api.gui.fireReactEvent("openFinanceWindow", "Finances")
			api.gui.fireReactEvent("uio.finances.view", "income")
		end,
		wait = 150,
		shot = "gallery_finances",
		check = function() return visible("menu.finance.window"), "finances" end,
	},
	{
		-- the line window: Vehicles card with Add/Remove Vehicle, the Stops card
		name = "gallery_line_window",
		pair = true,
		act = function(ctx)
			clear()
			if ctx.card_line then
				api.gui.camera.focusEntity(ctx.card_line)
				api.gui.fireReactEvent("selectEntity", { entity = ctx.card_line, stack = false })
			end
		end,
		wait = 180,
		shot = "gallery_line_window",
		check = function(ctx)
			-- the "before" shot (run.sh --vanilla) has no Stops card
			if fixture.vanilla then return ctx.card_line ~= nil, "line window (vanilla)" end
			return stops_card(ctx.card_line) or false, "line window"
		end,
	},
	{
		-- minimize: a vehicle window alone (the line window of the scene before would lie under it at the
		-- same place), then folded
		name = "gallery_minimize_open",
		act = function(ctx)
			clear()
			if ctx.card_vehicle then api.gui.fireReactEvent("selectEntity", { entity = ctx.card_vehicle, stack = false }) end
		end,
		-- long enough for the window it replaces to fade out (its title showed through)
		wait = 300,
		shot = "gallery_minimize_open",
		check = function() return true, "open" end,
	},
	{
		-- the mouse over the vehicle window's title row first (3440 x 1440 screen): the game then shows its
		-- pin button there, and the buttons before it move left
		name = "gallery_minimize_hover",
		act = function() if reference_screen() then mouse(3287, 42) end end,
		wait = 45,
		check = function() return true, "hover" end,
	},
	{
		-- a real click on the minimize button, where it sits once the pin shows: the debug event folds
		-- without one, and the game then shows the rename button's tooltip (its focus moves there); the
		-- cursor leaves the window before the shot
		name = "gallery_minimize_folded",
		act = function()
			if reference_screen() then mouse(3248, 42, true) else api.gui.fireReactEvent("uio.debug.minimize_all", nil) end
		end,
		wait = 120,
		shot = "gallery_minimize_folded",
		check = function()
			if reference_screen() then mouse(1720, 0) end
			return true, "folded"
		end,
	},
	{
		name = "gallery_minimize_restored",
		act = function()
			api.gui.fireReactEvent("uio.debug.minimize_all", nil)
			clear()
		end,
		wait = 30,
		check = function() return true, "restored" end,
	},
	{
		-- the map hover of a vehicle: the camera on it, the cursor on it
		name = "gallery_vehicle_hover",
		pair = true,
		act = function(ctx)
			clear()
			ctx.hover_vehicle = road_vehicle_en_route() or ctx.card_vehicle
			if ctx.hover_vehicle then api.gui.camera.focusEntity(ctx.hover_vehicle) end
		end,
		wait = 180,
		check = function(ctx) return ctx.hover_vehicle ~= nil, "camera on " .. tostring(ctx.hover_vehicle) end,
	},
	{
		name = "gallery_vehicle_hover_shot",
		pair = true,
		act = function()
			local data = api.gui.camera.getCameraData()
			local x, y = screen_of(data.x, data.y, 1.5)
			debugPrint(string.format("[testbench] gallery: vehicle at screen %.0f %.0f", x, y))
			mouse(x, y)
		end,
		wait = 300,
		shot = "gallery_vehicle_hover",
		check = function() return true, "hover" end,
	},
	{
		-- subsidy offers, made with the game's own debug event in the savegame copy; the simulation runs a
		-- moment so they reach the ridge, where they join the save's own offer (the third icon)
		name = "gallery_subsidy_spawn",
		act = function()
			clear()
			api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(1))
			for _i = 1, 2 do
				api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Subvention", "_debugSpawn", {}))
			end
		end,
		wait = 240,
		check = function() return true, "spawned" end,
	},
	{
		name = "gallery_subsidy_ridge",
		act = function() api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(0)) end,
		wait = 120,
		shot = "gallery_subsidy_ridge",
		check = function() return true, "the ridge" end,
	},
	{
		name = "gallery_subsidy_hover_3",
		-- the subsidy group (the offers spawned above), second in the ridge of the gallery's savegame
		-- (docs/gallery.md); its hover card lists the other offer below the shown one
		act = function() mouse(1238, 43) end,
		wait = 240,
		shot = "gallery_subsidy_hover_3",
		check = function() return true, "hover on icon 3" end,
	},
	{
		name = "gallery_subsidy_hover_4",
		act = function() mouse(1364, 47) end,
		wait = 240,
		shot = "gallery_subsidy_hover_4",
		check = function() return true, "hover on icon 4" end,
	},
	{
		-- catchment areas of all stations, passengers and cargo, over the station's town
		name = "gallery_catchment",
		act = function(ctx)
			clear()
			if ctx.terminal_station then api.gui.camera.focusEntity(ctx.terminal_station) end
			api.gui.fireReactEvent("uio.catchment", { person = true, cargo = true })
		end,
		wait = 120,
		check = function() return visible("uio.catchment.person"), "catchment" end,
	},
	{
		-- far enough out to see the areas of several stations
		name = "gallery_catchment_far",
		act = function()
			local data = api.gui.camera.getCameraData()
			local h = api.engine.terrain.getHeightAt(api.type.Vec2f.new(data.x, data.y))
			api.gui.camera.focusPosition(api.type.Vec3f.new(data.x, data.y, h), 1600)
		end,
		wait = 240,
		shot = "gallery_catchment",
		check = function() return true, "zoomed out" end,
	},
	{
		name = "gallery_warehouses",
		pair = true,
		act = function()
			api.gui.fireReactEvent("uio.catchment", { person = false, cargo = false })
			clear()
			api.gui.fireReactEvent("openStatisticsWindow", "Warehouse")
		end,
		wait = 150,
		shot = "gallery_warehouses",
		check = function() return visible("menu.statistics.window"), "warehouses" end,
	},
	{
		-- the windows side by side: Line Manager, Statistics with its quick filters, a vehicle window
		name = "gallery_overview",
		act = function(ctx)
			clear()
			api.gui.fireReactEvent("openStatisticsWindow", "Line")
			if ctx.models_line then api.gui.fireReactEvent("openVehicleManager", { openWithLineEntity = ctx.models_line }) end
			if ctx.card_line then api.gui.camera.focusEntity(ctx.card_line) end
			if ctx.card_vehicle then api.gui.fireReactEvent("selectEntity", { entity = ctx.card_vehicle, stack = false }) end
		end,
		wait = 240,
		shot = "gallery_overview",
		check = function() return true, "overview" end,
	},
	{
		name = "gallery_done",
		act = clear,
		wait = 10,
		check = function() return true, "done" end,
	},
}
if fixture.gallery then
	local selected = {} ---@type uo.testbench.GuiCheck[]
	-- run.sh --only: just those scenes, after the two that set the scene up
	local wanted = nil ---@type table<string, true>?
	if fixture.only and #fixture.only > 0 then
		wanted = { gallery_warm_up = true, gallery_start = true }
		for _i, name in ipairs(fixture.only) do wanted[name] = true end
	end
	for _i, scene in ipairs(scenes) do
		if (scene.pair or not fixture.vanilla) and (not wanted or wanted[scene.name]) then
			selected[#selected + 1] = scene
		end
	end
	return selected
end

-- Crash probe (gui/probe.script.lua): set PROBE = true to open its window variants first.
local PROBE = false
if PROBE then
	local probes = {} ---@type uo.testbench.GuiCheck[]
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
