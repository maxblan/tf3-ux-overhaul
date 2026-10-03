--- Construction menu (backlog F1-F3):
--   * the Rail and Tracks menus show each other's tabs, as do Road and Roads: stations, depots,
--     tracks and signals are one menu away from either game-bar button. Each button still opens on
--     its own first tab, so nothing moves away from where players look for it.
--   * tracks are listed fastest first, available ones before those not yet available, so the track
--     armed by default is the best one that can be built (base: slowest first)
--   * "Configure" in a station's window opens the modules menu on Tracks, Platforms, Road Access or
--     Building (the first one the station has) instead of Decoration: these tabs are ordered first.
--     (Switching the tab by event is not safe: the base handler mixes up tab indices when a menu has
--     hidden tabs and raises a Lua error, observed in-game.)
--   * the bulldozer's tooltip warns when the removal includes a station that lines stop at:
--     "Removes Blumenstrasse - 2 lines stop here" (the game has no undo; a confirmation dialog is not
--     possible from a mod, the tooltip is the last moment before the click)
-- Patches the exported functions construction_react_util.getMenuCategories and getActionParams
-- before the UI starts
-- (construction.script.lua); any error leaves the base result unchanged.
-- @module ui_overhaul.gui.construction
local construction_react_util = require("::/gui/construction/construction_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")

local construction = {}

local MERGED_MENUS = { { "RAIL", "TRACKS" }, { "ROAD", "ROADS" } }
local GUEST_ORDER_OFFSET = 100000 -- tabs from the partner menu come after the menu's own tabs
-- module tabs that should come first, in this order (base: Plots, Decoration, Platforms, ...)
local PREFERRED_MODULE_TABS = { modules_tracks = 1, modules_platforms = 2, modules_street_access = 3,
	modules_building = 4 }

local function by_order(a, b)
	local oa, ob = a[1].order or 0, b[1].order or 0
	if oa ~= ob then return oa < ob end
	return tostring(a[1].name) < tostring(b[1].name)
end

local function copy(t)
	local result = {}
	for k, v in pairs(t) do result[k] = v end
	return result
end

--- Adds `from`'s tabs (as copies placed after the own tabs) to `to`, from the unmerged lists.
local function add_guest_tabs(result, original, to, from)
	if not original[to] or not original[from] then return end
	local merged = {}
	for _i, entry in ipairs(original[to]) do merged[#merged + 1] = entry end
	for _i, entry in ipairs(original[from]) do
		local category = copy(entry[1])
		category.menu = to
		category.order = (category.order or 0) + GUEST_ORDER_OFFSET
		merged[#merged + 1] = { category, entry[2] }
	end
	table.sort(merged, by_order)
	result[to] = merged
end

local function track_speed(definition)
	local id = api.res.streetTemplateRep.find(definition.resName)
	if id < 0 then return 0 end
	local template = api.res.streetTemplateRep.get(id)
	return template.laneConfigs[1] and template.laneConfigs[1].speed or 0
end

local function available(definition)
	local year = api.engine.util.getYear()
	local a = definition.availability or {}
	return (a.yearFrom or 0) <= year and ((a.yearTo or 0) == 0 or a.yearTo > year)
end

local function sort_tracks(result)
	for _m, menu in pairs(result) do
		for _i, entry in ipairs(menu) do
			if entry[1].category == "tracks" then
				local keyed = {}
				for index, definition in ipairs(entry[2]) do
					keyed[index] = { definition = definition, available = available(definition),
						speed = track_speed(definition), index = index }
				end
				table.sort(keyed, function(a, b)
					if a.available ~= b.available then return a.available end
					if a.speed ~= b.speed then return a.speed > b.speed end
					return a.index < b.index
				end)
				for index, item in ipairs(keyed) do entry[2][index] = item.definition end
			end
		end
	end
end

local function order_module_tabs(result)
	local modules = result.MODULES
	if not modules then return end
	for index, entry in ipairs(modules) do
		local rank = PREFERRED_MODULE_TABS[entry[1].category]
		if rank then
			local category = copy(entry[1])
			category.order = -100 + rank
			modules[index] = { category, entry[2] }
		end
	end
	table.sort(modules, by_order)
end

local function describe(result)
	local parts = {}
	for menu, list in pairs(result) do parts[#parts + 1] = menu .. "=" .. #list end
	table.sort(parts)
	return table.concat(parts, " ")
end

local logged = false

local function adjust(result)
	local before = not logged and describe(result) or nil
	local original = {}
	for menu, list in pairs(result) do original[menu] = list end
	for _i, pair in ipairs(MERGED_MENUS) do
		add_guest_tabs(result, original, pair[1], pair[2])
		add_guest_tabs(result, original, pair[2], pair[1])
	end
	sort_tracks(result)
	order_module_tabs(result)
	if before then
		logged = true
		debugPrint("[ui_overhaul] construction menus: ", before, " -> ", describe(result))
	end
end

local function patch_menu_categories()
	local original = construction_react_util.getMenuCategories
	construction_react_util.getMenuCategories = function(...)
		local result = original(...)
		local ok, err = pcall(adjust, result)
		if not ok then debugPrint("[ui_overhaul] construction menu adjustments failed: ", tostring(err)) end
		return result
	end
end

-- Bulldozer warning ---------------------------------------------------------------------------------

--- Stations among the removed entities: stations themselves, or the stations of removed constructions.
local function removed_stations(proposal)
	local stations, seen = {}, {}
	local function add(station)
		if not seen[station] then
			seen[station] = true
			stations[#stations + 1] = station
		end
	end
	local removed = proposal.toRemove_native
	for index = 1, removed and removed:size() or 0 do
		local entity = removed:at(index)
		if api.engine.getComponent(entity, api.type.ComponentType.STATION) then add(entity) end
		local component = api.engine.getComponent(entity, api.type.ComponentType.CONSTRUCTION)
		for _i, station in ipairs(component and component.stations or {}) do add(station) end
	end
	return stations
end

local function station_warnings(proposal)
	local by_group, order = {}, {}
	for _i, station in ipairs(removed_stations(proposal)) do
		local group = api.engine.system.stationGroupSystem.getStationGroup(station)
		local entry = by_group[group]
		if not entry then
			entry = { lines = {}, count = 0 }
			by_group[group] = entry
			order[#order + 1] = group
		end
		for _j, line_and_stop in ipairs(api.engine.system.lineSystem.getLineStopsForStation(station)) do
			if not entry.lines[line_and_stop[1]] then
				entry.lines[line_and_stop[1]] = true
				entry.count = entry.count + 1
			end
		end
	end
	local strings = {}
	for _i, group in ipairs(order) do
		local count = by_group[group].count
		if count > 0 then
			-- plain _(): plural lookups (nGetText) do not see a mod's strings.json (observed in-game)
			local template = count == 1 and _("Removes {station} - {count} line stops here")
				or _("Removes {station} - {count} lines stop here")
			strings[#strings + 1] = lang_util.format(template,
				{ station = api.engine.util.getEntityName(group) or "", count = lang_util.formatInt(count) })
		end
	end
	return strings
end

construction.station_warnings = station_warnings -- for the testbench

local function patch_bulldozer_tooltip()
	local original = construction_react_util.getActionParams
	construction_react_util.getActionParams = function(...)
		local result = original(...)
		local action = result and result.constructionActionParams
		if action and action.bulldozer ~= nil and type(action.getProposalStringsFn) == "function" then
			local strings_fn = action.getProposalStringsFn
			action.getProposalStringsFn = function(proposal, proposal_data)
				local strings = strings_fn(proposal, proposal_data) or {}
				local ok, warnings = pcall(station_warnings, proposal)
				if ok then
					for _i, warning in ipairs(warnings) do table.insert(strings, 1, warning) end
				end
				return strings
			end
		end
		return result
	end
end

--- Called from the react-replacement-config before the UI starts.
function construction.install(_replacement_api)
	patch_menu_categories()
	patch_bulldozer_tooltip()
	debugPrint("[ui_overhaul] construction menu patch installed")
end

return construction
