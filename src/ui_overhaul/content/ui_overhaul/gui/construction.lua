--- Construction menu:
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
--     "Removes Blumenstrasse - 2 lines stop here" (the game has no undo and a mod cannot show a
--     confirmation dialog, so the tooltip is the last moment before the click)
--   * while drawing track or road, the same tooltip measures what is drawn: steepest gradient and
--     tightest curve radius, each with the type's build limit, the height range, and how high
--     bridges and how deep tunnels run above or below the ground (core/geometry.lua)
-- Patches the exported functions construction_react_util.getMenuCategories and getActionParams
-- before the UI starts (construction.script.lua); any error leaves the base result unchanged.
-- @module ui_overhaul.gui.construction
local construction_react_util = require("::/gui/construction/construction_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local geometry = require("/ui_overhaul/core/geometry.lua")

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

-- Measurements while drawing track or road --------------------------------------------------------

local function vec(v) return { x = v.x, y = v.y, z = v.z } end

local function edge(comp)
	return { p0 = vec(comp.position0), p1 = vec(comp.position1), t0 = vec(comp.tangent0), t1 = vec(comp.tangent1),
		type = comp.type }
end

-- Items of an engine list: a native vector (size/at) or a Lua list.
local function items(list)
	if list == nil then return {} end
	local ok, size = pcall(function() return list:size() end)
	local result = {}
	if ok then
		for i = 1, size do result[i] = list:at(i) end
	else
		for i, item in ipairs(list) do result[i] = item end
	end
	return result
end

-- Height of the ground under `p`, or nil if the terrain cannot be read here.
local function ground(p)
	local ok, height = pcall(api.engine.terrain.getHeightAt, api.type.Vec2f.new(p.x, p.y))
	return ok and type(height) == "number" and height or nil
end

--- Plain measurements of the edges of `kind` (0 street, 1 track) that the proposal adds.
local function measure(proposal, kind)
	local street = proposal.proposal
	local edges, removed = {}, {}
	for _i, segment in ipairs(items(street.addedSegments_native or street.addedSegments)) do
		if segment.type == kind then edges[#edges + 1] = edge(segment.comp) end
	end
	for _i, segment in ipairs(items(street.removedSegments)) do removed[#removed + 1] = edge(segment.comp) end
	local summary = geometry.summary(edges, removed)
	if not summary then return nil end
	-- bridges and tunnels: largest distance to the ground along them
	local base_type = api.type.enum.BaseEdgeType
	for _i, e in ipairs(edges) do
		if e.type == base_type.BRIDGE or e.type == base_type.TUNNEL then
			for _j, p in ipairs(geometry.edge_metrics(e).points) do
				local g = ground(p)
				if g then
					if e.type == base_type.BRIDGE then
						summary.above = math.max(summary.above or 0, p.z - g)
					else
						summary.below = math.max(summary.below or 0, g - p.z)
					end
				end
			end
		end
	end
	return summary
end

local function template_limits(res_name)
	local id = res_name and api.res.streetTemplateRep.find(res_name) or -1
	if id < 0 then return {} end
	local template = api.res.streetTemplateRep.get(id)
	return { max_slope = template.maxSlopeBuild, min_radius = template.minCurveRadiusBuild }
end

local function metres(value)
	return api.util.formatLength(value)
end

--- Tooltip lines for a drawn track or road.
local function measurement_strings(proposal, kind, res_name)
	local m = measure(proposal, kind)
	if not m then return {} end
	local limits = template_limits(res_name)
	local strings = {}
	local grade = api.util.toStringPercentPrecision(m.max_grade, 1)
	if limits.max_slope and limits.max_slope > 0 then
		strings[#strings + 1] = lang_util.format(_("Gradient: up to {value} (limit {limit})"),
			{ value = grade, limit = api.util.toStringPercentPrecision(limits.max_slope, 1) })
	else
		strings[#strings + 1] = lang_util.format(_("Gradient: up to {value}"), { value = grade })
	end
	if m.min_radius < 100000 then
		if limits.min_radius and limits.min_radius > 0 then
			strings[#strings + 1] = lang_util.format(_("Curve radius: {value} (minimum {limit})"),
				{ value = metres(m.min_radius), limit = metres(limits.min_radius) })
		else
			strings[#strings + 1] = lang_util.format(_("Curve radius: {value}"), { value = metres(m.min_radius) })
		end
	else
		strings[#strings + 1] = _("Curve radius: straight")
	end
	if m.z_max - m.z_min < 0.5 then
		strings[#strings + 1] = lang_util.format(_("Elevation: {value}"), { value = metres(m.z_min) })
	else
		strings[#strings + 1] = lang_util.format(_("Elevation: {from} to {to}"),
			{ from = metres(m.z_min), to = metres(m.z_max) })
	end
	if m.above and m.above >= 0.5 then
		strings[#strings + 1] = lang_util.format(_("Bridge: up to {value} above ground"), { value = metres(m.above) })
	end
	if m.below and m.below >= 0.5 then
		strings[#strings + 1] = lang_util.format(_("Tunnel: up to {value} below ground"), { value = metres(m.below) })
	end
	return strings
end

construction.measurement_strings = measurement_strings -- for the testbench

-- Wraps the action's getProposalStringsFn: `extra(proposal)` returns lines; `first` puts them first.
local function add_strings(action, extra, first)
	local strings_fn = action.getProposalStringsFn
	action.getProposalStringsFn = function(proposal, proposal_data)
		local strings = strings_fn(proposal, proposal_data) or {}
		local ok, lines = pcall(extra, proposal)
		if ok then
			for i, line in ipairs(lines) do
				if first then table.insert(strings, i, line) else strings[#strings + 1] = line end
			end
		end
		return strings
	end
end

local function patch_proposal_tooltips()
	local original = construction_react_util.getActionParams
	construction_react_util.getActionParams = function(...)
		local result = original(...)
		local action = result and result.constructionActionParams
		if action and type(action.getProposalStringsFn) == "function" then
			if action.bulldozer ~= nil then
				add_strings(action, station_warnings, true)
			elseif action.trackEdgeBuilder ~= nil then
				local res_name = action.trackEdgeBuilder.resName
				add_strings(action, function(proposal) return measurement_strings(proposal, 1, res_name) end)
			elseif action.streetEdgeBuilder ~= nil then
				local res_name = action.streetEdgeBuilder.resName
				add_strings(action, function(proposal) return measurement_strings(proposal, 0, res_name) end)
			end
		end
		return result
	end
end

--- Called from the react-replacement-config before the UI starts.
function construction.install(_replacement_api)
	patch_menu_categories()
	patch_proposal_tooltips()
	debugPrint("[ui_overhaul] construction menu patch installed")
end

return construction
