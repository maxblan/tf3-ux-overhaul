--- Line Manager, "Select Terminals" popover of a stop: each terminal has three toggle buttons
-- [Don't Use | Alternative | Preferred] instead of the drop-down list, so one click sets its usage
-- (base: open the list, then pick). The preferred terminal's row is highlighted; its Don't Use and
-- Alternative buttons are disabled, as the base list is, and say why. Terminals the line's vehicles
-- cannot use (other carrier, passenger terminal for a freight line and the reverse), terminals the line's
-- vehicles cannot get to from the stop before or on to the stop after (the engine's path search, cached per
-- line version), and terminals a path problem starts or ends at are greyed, with the reason in the
-- tooltip; they stay clickable, as
-- the player may be about to build the missing track. Everything else in the popover is the base
-- popover; the problem arrow of a terminal is also shown on the right terminal only (base compares
-- terminal numbers modulo the stop count), and outside the Line Manager the mod computes the problems
-- itself (core/line_problems.lua), where the base popover would show none.
--
-- A Lua conversion of the base recipe TerminalSelection (gui/line_vehicle_mgmt/line_manager_panel.tl),
-- registered under the base name so the base stylesheet applies. The base recipe is file-local, so it
-- cannot be replaced: instead the exported module function popover_react_util.PopoverWindowContent,
-- which PopoverWindow looks up each time it renders, is wrapped; for the terminal popover only, the
-- wrapper hands it Popover (this recipe inside a recipe of its own name) instead of the base one. Other
-- mods that replace the recipe PopoverWindowContent (e.g. Auto Assign Terminals) still see the same
-- parameters. A mod that swaps the base popover by name (Easy Terminal Assignment) and wraps the same
-- function: the one that comes first in the mod list wins (priority.lua). If rendering fails, the base
-- popover is shown. Installed by installer.lua.
--
-- TerminalButton opens the same popover outside the Line Manager (station window, line window). Its
-- parameters have the shape of the Line Manager's, with the line read from the game and each change
-- sent as a line update. Where a mod that swaps the popover comes first, it gets the base name so that
-- mod shows its own popover here too. Popover moves onto the screen once laid out, where the game left
-- it reaching past the right or bottom edge (wide screens, stops near the edge).
-- @module ui_overhaul.gui.terminals
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local line_util = require("::/gui/line_vehicle_mgmt/line_util.tl")
local popover_react_util = require("::/gui/main/popover_react_util.tl")
local react = require("::/gui/main/react.lua")
local styleutil = require("::/gui/main/styleutil.tl")
local table_util = require("::/scripts/table_util.tl")
local line_problems = require("/ui_overhaul/core/line_problems.lua")
local fallback = require("/ui_overhaul/gui/fallback.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")
local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")

---@class uo.gui.terminals
local terminals = {}

---@alias uo.gui.terminals.Usage "Unused"|"Alternative"|"Main"

---A terminal of the popover's stop (the base TerminalData).
---@class uo.gui.terminals.TerminalData
---@field number integer 1-based over all terminals of the station group
---@field current boolean the stop's preferred terminal
---@field stationEntity Engine.Entity
---@field stationIndex1 integer
---@field terminalIndex1 integer
---@field hasOverlength boolean
---@field alternativeHere boolean
---@field terminalSpecialization? string cargo class name, "UNIVERSAL", nil without transfer speeds
---@field terminalLength number
---@field isPassengerTerminal boolean
---@field isCargoTerminal boolean

---The entries of the Line Manager's iconPaths (LVMIconPaths) the popover uses.
---@class uo.gui.terminals.IconPaths
---@field problemAlert string
---@field problemArrow string

---The line state handed to other mods' popovers, as the Line Manager's lineState:old().
---@class uo.gui.terminals.LineStateView
---@field old fun(self: uo.gui.terminals.LineStateView): game.gui.line_vehicle_mgmt.line.ReactLine?

---The part of the Line Manager's CommonActionParams the popover uses (line_util.d.tl).
---@class uo.gui.terminals.CommonParams
---@field lineState? uo.gui.terminals.LineStateView set outside the Line Manager, for other mods' popovers
---@field iconPaths uo.gui.terminals.IconPaths
---@field changeMainTerminal fun(stopNumber: integer, stationIndex1: integer, terminalIndex1: integer)
---@field selectAlternativeTerminal fun(stopNumber: integer, station1: integer, terminal1: integer, add: boolean)

---The via state of the popover (a react.State in the Line Manager).
---@class uo.gui.terminals.ViaState
---@field old fun(self: uo.gui.terminals.ViaState): game.gui.line_vehicle_mgmt.line.ReactVia[]?

---Params of the TerminalSelection recipe (line_manager_panel.tl TerminalSelectionParams).
---@class uo.gui.terminals.Params
---@field commonParams uo.gui.terminals.CommonParams
---@field viaState uo.gui.terminals.ViaState
---@field lineEntity Engine.Entity
---@field stopNumber integer the stop's number in the path (stops and waypoints)
---@field stopIndex integer 0-based among the stops
---@field stopCount integer
---@field index2problems? table<integer, uo.core.line_problems.Problem[]>
---@field onClose? fun()
---@field place? fun(left: number, top: number, right: number, bottom: number) set by `open`: moves the popover so
--- that its content, measured at this rectangle, lies on the screen

---What read_problems copies from the engine for line_problems.index2problems.
---@class uo.gui.terminals.ProblemData
---@field stops uo.core.line_problems.Stop[]
---@field segments uo.core.line_problems.State[][]

---Why the line cannot use a terminal: kind, and for "from" / "to" the station it cannot reach.
---@class uo.gui.terminals.Issue
---@field kind uo.core.line_problems.Incompatibility|"from"|"to"
---@field station? string

---Path search results of one line stop, by terminal number (false: reachable).
---@class uo.gui.terminals.ReachEntry
---@field revision string
---@field time number
---@field used? number
---@field results table<integer, uo.gui.terminals.Issue|false>

---The line state outside the Line Manager.
---@class uo.gui.terminals.LineState
---@field old fun(): game.gui.line_vehicle_mgmt.line.ReactLine?
---@field reset fun()

---@class uo.gui.terminals.TerminalButtonParams: react.Param
---@field id string component id, unique among all open windows
---@field line Engine.Entity
---@field stopIndex0 integer 0-based, without waypoints
---@field problem? string why the line's vehicles cannot reach the stop, shown above the tooltip

local BASE_NAME = "TerminalSelection"

-- Button order and values as in the base drop-down list.
---@type uo.gui.terminals.Usage[]
local USAGES = { "Unused", "Alternative", "Main" }

-- The base recipe, taken from the first terminal popover of the Line Manager (it is file-local there,
-- and the game's debug library cannot reach it otherwise); until then `Vanilla` stands in for it.
---@type react.Recipe<uo.gui.terminals.Params>?
local base_recipe

local report = guard.reporter("terminal selection: ")

-- Terminals of the stop (base getter, unchanged except that the overlength check runs once per stop).
-- Engine reads only; runs every step.
---@param params uo.gui.terminals.Params
---@return uo.gui.terminals.TerminalData[]
local function read_terminals(params)
	local vias = params.viaState:old()
	---@cast vias -nil -- the caller (render's hook) checked has_via()
	local stop = vias[params.stopNumber].stop
	---@cast stop -nil -- the popover belongs to a stop, not a waypoint
	local stationGroup = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
	---@cast stationGroup -nil -- a line stop's station group always has this component

	local stationTerminal2overlength = api.engine.system.transportVehicleSystem.checkLineStopForVehicleOverlength(
		params.lineEntity,
		params.stopIndex
	)

	local result = {}
	local terminalIndex = 1
	for stationIndex1, stationEntity in ipairs(stationGroup.stations) do
		local station = api.engine.getComponent(stationEntity, api.type.ComponentType.STATION)

		---@cast station -nil -- the stations of a station group have this component
		for terminalIndex1, terminal in ipairs(station.terminals) do
			local alternativeHere = false
			for _i, alternative in ipairs(stop.alternativeTerminals) do
				if alternative.station + 1 == stationIndex1 and alternative.terminal + 1 == terminalIndex1 then
					alternativeHere = true
				end
			end

			---@type string?
			local terminalSpecialization
			for _i, transferSpeed in ipairs(terminal.cargoTransferSpeeds) do
				for _j, class in ipairs(transferSpeed.cargoTypeSet.cargoClassesIncluded) do
					terminalSpecialization = class
				end
			end
			local isPassengerTerminal = terminal.passengersLoad or terminal.passengersUnload
			local isCargoTerminal = terminal.cargoLoad or terminal.cargoUnload

			local terminalLength = line_util.getTerminalLength(stationEntity, terminalIndex1)

			local hasOverlength = false
			local stationIndex0 = stationIndex1 - 1
			local terminalIndex0 = terminalIndex1 - 1
			for stationTerminal, _v in pairs(stationTerminal2overlength) do
				if stationTerminal.station == stationIndex0 and stationTerminal.terminal == terminalIndex0 then
					hasOverlength = true
				end
			end

			table.insert(result, {
				number = terminalIndex,
				current = stop.station1 == stationIndex1 and stop.terminal1 == terminalIndex1,
				stationEntity = stationEntity,
				stationIndex1 = stationIndex1,
				terminalIndex1 = terminalIndex1,
				hasOverlength = hasOverlength,
				alternativeHere = alternativeHere,
				terminalSpecialization = terminalSpecialization,
				terminalLength = terminalLength,
				isPassengerTerminal = isPassengerTerminal,
				isCargoTerminal = isCargoTerminal,
			})
			terminalIndex = terminalIndex + 1
		end
	end
	return result
end

--- Usage of a terminal: "Main" (preferred), "Alternative" or "Unused".
---@param terminalData uo.gui.terminals.TerminalData
---@return uo.gui.terminals.Usage
function terminals.usage(terminalData)
	if terminalData.current then return "Main" end
	if terminalData.alternativeHere then return "Alternative" end
	return "Unused"
end

--- The one call that sets `usage` for a terminal currently used as `current`, as the base list does on
-- a change: Preferred -> changeMainTerminal, Alternative / Don't Use -> selectAlternativeTerminal.
-- Only one call per click: a second one in the same frame would start from the old line state and undo
-- the first. Nothing for the preferred terminal (the base list is disabled there) or an unchanged usage.
---@param commonParams uo.gui.terminals.CommonParams
---@param stopNumber integer
---@param terminalData uo.gui.terminals.TerminalData
---@param current uo.gui.terminals.Usage
---@param usage? uo.gui.terminals.Usage
---@return boolean sent
function terminals.apply(commonParams, stopNumber, terminalData, current, usage)
	if usage == nil or usage == current or current == "Main" then return false end
	if usage == "Main" then
		commonParams.changeMainTerminal(stopNumber, terminalData.stationIndex1, terminalData.terminalIndex1)
	else
		commonParams.selectAlternativeTerminal(stopNumber, terminalData.stationIndex1, terminalData.terminalIndex1,
			usage == "Alternative")
	end
	return true
end

-- [Don't Use | Alternative | Preferred], the current usage checked. The preferred terminal keeps its
-- Preferred button lit (it stands out instead of looking switched off); the other two are disabled
-- there, as the base list is, since a stop always needs a preferred terminal.
---@param params uo.gui.terminals.Params
---@param terminalData uo.gui.terminals.TerminalData
---@return react.TreeNodeId
local function usage_buttons(params, terminalData)
	local current = terminals.usage(terminalData)
	local preferred = current == "Main"
	local labels = { _("Don't Use"), _("Alternative"), _("Preferred") }
	---@type builtin.ToggleButtonGroupChildParam[], integer
	local buttons, selected = {}, 1
	for i, usage in ipairs(USAGES) do
		local enabled = not preferred or usage == "Main"
		buttons[i] = {
			meta = {
				enabled = enabled,
				tooltip = not enabled and _("Make another terminal preferred first.") or nil,
			},
			content = builtin.TextView{ meta = { class = "font-scale-annotation" }, text = labels[i] },
		}
		if usage == current then selected = i end
	end
	return builtin.ToggleButtonGroup{
		meta = {
			-- the class scopes this popover's rules (terminals.css.lua): other mods' popovers have the
			-- base recipe's name too
			class = "uio-terminal-usage",
			id = "uio.terminals.usage." .. tostring(terminalData.number),
			tooltip = _("Set Terminal Usage"),
		},
		buttons = buttons,
		selected = selected,
		onValueChange = function(index)
			terminals.apply(params.commonParams, params.stopNumber, terminalData, current, USAGES[index])
		end,
	}
end

-- Problems outside the Line Manager -------------------------------------------------------------

-- Flat 0-based terminal index of a stop in its station group (base: flattenTerminalIndex).
---@param stop Engine.Component.Line.Stop
---@return integer
local function flat_terminal(stop)
	local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
	local index = stop.terminal
	for station_index1, station_entity in ipairs(group and group.stations or {}) do
		if stop.station + 1 == station_index1 then return index end
		local station = api.engine.getComponent(station_entity, api.type.ComponentType.STATION)
		---@cast station -nil -- the stations of a station group have this component
		index = index + #station.terminals
	end
	return 0
end

---@param location? UtilLine.PathProblemLocation
---@return game.gui.line_vehicle_mgmt.line_util.RelaxationType?
local function relaxation(location)
	if not location then return nil end
	return line_util.getRelaxationType(location.okModes, location.relaxedModes, location.allowedModes)
end

--- Plain copy of the line's stops and detailed problems for line_problems.index2problems: stops and
-- waypoints in line order (stops carry `stopIndex`, 1-based), segments of plain stop states. Engine
-- reads only (timer callback): names untranslated, reasons as relaxation types.
---@param line Engine.Entity
---@return uo.gui.terminals.ProblemData?
function terminals.read_problems(line)
	local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
	if not component then return nil end
	---@type uo.core.line_problems.Stop[]
	local stops = {}
	for stop_index, stop in ipairs(component.stops) do
		stops[#stops + 1] = {
			name = api.engine.util.getEntityName(stop.stationGroup),
			terminal0 = flat_terminal(stop),
			stopIndex = stop_index,
		}
		for _j in ipairs(stop.waypoints) do stops[#stops + 1] = { terminal0 = line_problems.WAYPOINT } end
	end
	---@type uo.core.line_problems.State[][]
	local segments = {}
	for _i, segment in ipairs(api.engine.util.line.getDetailedLineProblems(line)) do
		---@type uo.core.line_problems.State[]
		local states = {}
		for _j, state in ipairs(segment) do
			local from, to = state.noPathFromAlternative, state.noPathToAlternative
			states[#states + 1] = {
				noPath = state.noPath or nil,
				duplicate = state.duplicateStop or nil,
				incompatible = state.incompatibleStop or nil,
				reason = state.noPath and relaxation(state.noPathLocation) or nil,
				fromAlternative = from and { from[1], relaxation(from[2]) } or nil,
				toAlternative = to and { to[1], relaxation(to[2]) } or nil,
			}
		end
		segments[#segments + 1] = states
	end
	return { stops = stops, segments = segments }
end

-- Base text of a problem (line_manager_panel.tl, the same strings, kept on one line each so the strings
-- check finds them). GUI thread only.
-- luacheck: push ignore 631
---@param problem uo.core.line_problems.Problem
---@return string
function terminals.problem_text(problem)
	local q = problem.params
	if problem.kind == "duplicate" then return _("The same station appears twice consecutively.") end
	if problem.kind == "incompatible" then return _("The stop is incompatible.") end
	local f = {
		origin = q.originIsWaypoint and _("Waypoint") or q.origin or _("Station"),
		destination = q.destinationIsWaypoint and _("Waypoint") or q.destination or _("Station"),
		terminalOrigin = lang_util.formatInt(q.terminalOrigin),
		terminalDestination = lang_util.formatInt(q.terminalDestination),
		reason = q.reason and line_util.getRelaxationText(q.reason) or nil,
	}
	local r = f.reason ~= nil
	---@type string
	local text
	if problem.kind == "no_path" then
		if q.originIsWaypoint and q.destinationIsWaypoint then
			text = r and _("No path from {origin} to {destination}: {reason}.")
				or _("No path from {origin} to {destination} exists.")
		elseif q.originIsWaypoint then
			text = r and _("No path from {origin} to {destination} [Terminal {terminalDestination}]: {reason}.")
				or _("No path from {origin} to {destination} [Terminal {terminalDestination}] exists.")
		elseif q.destinationIsWaypoint then
			text = r and _("No path from {origin} [Terminal {terminalOrigin}] to {destination}: {reason}.")
				or _("No path from {origin} [Terminal {terminalOrigin}] to {destination} exists.")
		else
			text = r and _("No path from {origin} [Terminal {terminalOrigin}] to {destination} [Terminal {terminalDestination}]: {reason}.")
				or _("No path from {origin} [Terminal {terminalOrigin}] to {destination} [Terminal {terminalDestination}] exists.")
		end
	elseif problem.kind == "from_alternative_to_alternative" then
		text = r and _("No path from alternative stop {origin} [Terminal {terminalOrigin}] to alternative {destination} [Terminal {terminalDestination}] exists: {reason}.")
			or _("No path from alternative stop {origin} [Terminal {terminalOrigin}] to alternative {destination} [Terminal {terminalDestination}] exists.")
	elseif problem.kind == "from_alternative" then
		text = r and _("No path from alternative stop {origin} [Terminal {terminalOrigin}] to {destination} [Terminal {terminalDestination}] exists: {reason}.")
			or _("No path from alternative stop {origin} [Terminal {terminalOrigin}] to {destination} [Terminal {terminalDestination}] exists.")
	else
		text = r and _("No path from {origin} [Terminal {terminalOrigin}] to alternative stop {destination} [Terminal {terminalDestination}] exists: {reason}.")
			or _("No path from {origin} [Terminal {terminalOrigin}] to alternative stop {destination} [Terminal {terminalDestination}] exists.")
	end
	return lang_util.format(text, f)
end
-- luacheck: pop

--- index2problems in the Line Manager's shape (with tooltips) from read_problems' data.
---@param data uo.gui.terminals.ProblemData
---@return table<integer, uo.core.line_problems.Problem[]>
local function own_index2problems(data)
	local result = line_problems.index2problems(data.stops, data.segments)
	for _index, problems in pairs(result) do
		for _i, problem in ipairs(problems) do problem.tooltip = terminals.problem_text(problem) end
	end
	return result
end

---@param list? Carrier[]
---@return table<Carrier, true>
local function carrier_set(list)
	---@type table<Carrier, true>
	local set = {}
	for _i, carrier in ipairs(list or {}) do set[carrier] = true end
	return set
end

--- What the line's vehicles carry, for line_problems.incompatibility. Without vehicles, the carriers
-- of the other stops' preferred terminals. Engine reads only.
---@param line Engine.Entity
---@param stop_index0 integer
---@return uo.core.line_problems.Needs
local function read_line_needs(line, stop_index0)
	---@type uo.core.line_problems.Needs
	local needs = { carriers = {}, passengers = false, cargo = false }
	for _i, vehicle in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
		if tv then needs.carriers[tv.carrier] = true end
	end
	if next(needs.carriers) == nil then
		local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
		for i, stop in ipairs(component and component.stops or {}) do
			if i - 1 ~= stop_index0 then
				local carriers = api.engine.system.stationGroupSystem.getCarriers(stop.stationGroup, stop.station, stop.terminal)
				for carrier in pairs(carrier_set(carriers and carriers[1])) do needs.carriers[carrier] = true end
			end
		end
	end
	local passenger_id = api.res.cargoTypeRep.getPassengerCargoTypeId()
	for index, usage in pairs(api.engine.util.line.getLineCapacityUsages(line, false) or {}) do
		if usage.capacity > 0 then
			if index - 1 == passenger_id then needs.passengers = true else needs.cargo = true end
		end
	end
	return needs
end

-- Vehicle nodes of the preferred terminal of an engine line stop.
---@param stop Engine.Component.Line.Stop
---@return NodeId[]?
local function stop_nodes(stop)
	local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
	local station_entity = group and group.stations[stop.station + 1]
	local station = station_entity and api.engine.getComponent(station_entity, api.type.ComponentType.STATION)
	local terminal = station and station.terminals[stop.terminal + 1]
	return terminal and { terminal.vehicleNodeId } or nil
end

-- Path search results per line and stop, for one line version and at most REACH_SECONDS: the
-- search is the expensive part, and building or removing track changes the answer without changing
-- the line. Entries not used for PRUNE_SECONDS are dropped.
---@type table<string, uo.gui.terminals.ReachEntry>
local reach_cache = {}
local REACH_SECONDS, PRUNE_SECONDS = 10, 120

---@param line Engine.Entity
---@return string
local function revision_key(line)
	local r = api.engine.getRevision(line)
	return table.concat({ r.num[1], r.num[2], r.num[3] }, ".")
end

-- The cached results of `line`'s stop `stop_index0` (number -> result or false), fresh if needed.
---@param line Engine.Entity
---@param stop_index0 integer
---@return table<integer, uo.gui.terminals.Issue|false>
local function reach_entry(line, stop_index0)
	local now = guard.clock() or 0
	local slot = tostring(line) .. "/" .. tostring(stop_index0)
	local revision = revision_key(line)
	local entry = reach_cache[slot]
	if not entry or entry.revision ~= revision or now - entry.time > REACH_SECONDS then
		for key, old in pairs(reach_cache) do
			if now - old.used > PRUNE_SECONDS then reach_cache[key] = nil end
		end
		entry = { revision = revision, time = now, results = {} }
		reach_cache[slot] = entry
	end
	entry.used = now
	return entry.results
end

--- Whether the line's vehicles can get to a terminal from the stop before and on to the stop after
-- (the engine's path search with the line's transport modes): nil if they can, else
-- { kind = "from" | "to", station = name }. `stop_index0` is the stop of the popover.
---@param line Engine.Entity
---@param component Engine.Component.Line
---@param stop_index0 integer
---@param node NodeId
---@param number integer
---@param modes TransportMode[]
---@return uo.gui.terminals.Issue?
local function terminal_reach(line, component, stop_index0, node, number, modes)
	local count = #component.stops
	if count < 2 or #modes == 0 then return nil end
	local results = reach_entry(line, stop_index0)
	local cached = results[number]
	if cached ~= nil then return cached or nil end
	local before = component.stops[((stop_index0 - 1) % count) + 1]
	local after = component.stops[((stop_index0 + 1) % count) + 1]
	local find = api.engine.util.pathfinding.findPathNodeToNode
	---@type uo.gui.terminals.Issue|false
	local result = false
	local before_nodes, after_nodes = stop_nodes(before), stop_nodes(after)
	if before_nodes and #find(before_nodes, { node }, modes) == 0 then
		result = { kind = "from", station = api.engine.util.getEntityName(before.stationGroup) }
	elseif after_nodes and #find({ node }, after_nodes, modes) == 0 then
		result = { kind = "to", station = api.engine.util.getEntityName(after.stationGroup) }
	end
	results[number] = result
	return result or nil
end

--- terminal number -> why the line cannot use it ({ kind, station }), for the stop of the popover:
-- vehicles that cannot stop there, or no path to it from the stop before or on to the stop after.
-- Engine reads only.
---@param params uo.gui.terminals.Params
---@return table<integer, uo.gui.terminals.Issue>
local function read_incompatible(params)
	local vias = params.viaState:old()
	---@cast vias -nil -- the caller (render's hook) checked has_via()
	local stop = vias[params.stopNumber].stop
	---@cast stop -nil -- the popover belongs to a stop, not a waypoint
	local group_entity = stop.stationGroup
	local group = api.engine.getComponent(group_entity, api.type.ComponentType.STATION_GROUP)
	---@cast group -nil -- a line stop's station group always has this component
	local line = params.lineEntity
	local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
	local needs = read_line_needs(line, params.stopIndex)
	---@type TransportMode[]
	local modes = {}
	for mode, on in pairs(api.engine.util.line.getLineTransportModesUnion(line) or {}) do
		if on then modes[#modes + 1] = mode end
	end
	---@type table<integer, uo.gui.terminals.Issue>, integer
	local result, number = {}, 0
	for station_index1, station_entity in ipairs(group.stations) do
		local station = api.engine.getComponent(station_entity, api.type.ComponentType.STATION)
		---@cast station -nil -- the stations of a station group have this component
		for terminal_index1, terminal in ipairs(station.terminals) do
			number = number + 1
			local carriers = api.engine.system.stationGroupSystem.getCarriers(group_entity, station_index1 - 1,
				terminal_index1 - 1)
			local kind = line_problems.incompatibility({
				carriers = carrier_set(carriers and carriers[1]),
				passengers = terminal.passengersLoad or terminal.passengersUnload,
				cargo = terminal.cargoLoad or terminal.cargoUnload,
			}, needs)
			if kind then
				result[number] = { kind = kind }
			elseif component then
				local ok, reach = pcall(terminal_reach, line, component, params.stopIndex, terminal.vehicleNodeId,
					number, modes)
				if ok then result[number] = reach else report("path search", reach) end
			end
		end
	end
	return result
end

--- What a terminal serves, as the base popover labels it, and the cargo class's colour if it has one.
-- A cargo terminal without a cargo class (no transfer speeds) takes every cargo, as "UNIVERSAL" does
-- (base: passes nil on to getCargoClassId, which takes a string).
---@param terminalData uo.gui.terminals.TerminalData
---@return string text
---@return Vec3f? color
function terminals.terminal_label(terminalData)
	local terminalText = _("Passenger and Cargo")
	---@type Vec3f?
	local bubbleColor
	local specialization = terminalData.terminalSpecialization
	if terminalData.isPassengerTerminal then
		if not terminalData.isCargoTerminal then
			terminalText = _("Passenger")
		end
	else
		if specialization ~= nil and specialization ~= "UNIVERSAL" then
			local cargoClassId = api.res.cargoClassRep.getCargoClassId(specialization)
			if cargoClassId ~= -1 then
				local specializationData = api.res.cargoClassRep.get(cargoClassId)

				terminalText = specializationData.name
				bubbleColor = specializationData.color
			end
		else
			terminalText = _("All Cargo Types")
		end
	end
	return terminalText, bubbleColor
end

---@param issue? uo.gui.terminals.Issue
---@return string?
local function incompatibility_text(issue)
	if not issue then return nil end
	local kind = issue.kind
	if kind == "carrier" then return _("The vehicles of this line cannot stop at this terminal.") end
	if kind == "passengers_only" then return _("Passenger terminal: this line carries only cargo.") end
	if kind == "cargo_only" then return _("Cargo terminal: this line carries only passengers.") end
	if kind == "from" then
		return lang_util.format(_("Vehicles of this line cannot get here from {station}."),
			{ station = issue.station or "" })
	end
	if kind == "to" then
		return lang_util.format(_("Vehicles of this line cannot get from here to {station}."),
			{ station = issue.station or "" })
	end
	return nil
end

---@param params uo.gui.terminals.Params
---@return react.TreeNodeId
local function render(params)
	-- The hooks come before the base's check for a missing via state, so they are the same on every
	-- render. Without a via state the popover shows nothing, so their callbacks read nothing then.
	---@return boolean
	local function has_via()
		return params.viaState ~= nil and params.viaState:old() ~= nil
	end
	---@type react.State<uo.gui.terminals.TerminalData[]>
	local terminalsState = engine_react_util.useStepState(
	---@param old? uo.gui.terminals.TerminalData[]
	---@return uo.gui.terminals.TerminalData[]
	function(old)
		if not has_via() then return old or {} end
		local ok, result = pcall(read_terminals, params)
		if ok then return result end
		report("read", result)
		return old or {}
	end)

	-- The Line Manager hands over its problems; the station and line window popovers have none.
	local own_problems = next(params.index2problems or {}) == nil
	---@param old? uo.gui.terminals.ProblemData
	---@return uo.gui.terminals.ProblemData?
	local problemsState = engine_react_util.useStepStateTimer(function(old)
		if not own_problems or not has_via() then return nil end
		local ok, result = pcall(terminals.read_problems, params.lineEntity)
		if ok then return result end
		report("problems", result)
		return old
	end, 1.0)
	---@param old? table<integer, uo.gui.terminals.Issue>
	---@return table<integer, uo.gui.terminals.Issue>
	local incompatibleState = engine_react_util.useStepStateTimer(function(old)
		if not has_via() then return old or {} end
		local ok, result = pcall(read_incompatible, params)
		if ok then return result end
		report("compatibility", result)
		return old or {}
	end, 1.0)
	if not has_via() then
		return builtin.BoxLayout{}
	end
	local index2problems = params.index2problems or {}
	if own_problems and problemsState:old() then
		local ok, result = pcall(own_index2problems, problemsState:old())
		if ok then index2problems = result else report("problem texts", result) end
	end
	local incompatible = incompatibleState:old() or {}

	local selectTerminalsHeader = builtin.Component{
		meta = {
			class = "select-terminals-header",
		},
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.TextView{
					meta = {
						class = "font-scale-headline",
					},
					text = lang_util.format(_("Terminals for Stop {stopnumber}"), {
						stopnumber = lang_util.formatInt(params.stopNumber),
					}),
				},
			},
		},
	}

	---@type react.TreeNodeId[]
	local children = {}
	for terminalNumber, terminalData in ipairs(terminalsState:old()) do
		local terminalText, bubbleColor = terminals.terminal_label(terminalData)

		local problemsPrev = index2problems[(params.stopNumber - 1) % params.stopCount]
		if not problemsPrev then
			problemsPrev = {}
		end
		local problemsThis = index2problems[params.stopNumber]
		if not problemsThis then
			problemsThis = {}
		end
		local problemPrev = false
		local problemThis = false
		local problemTooltipPrev = nil
		local problemTooltipThis = nil
		for _i, problem in ipairs(problemsPrev) do
			if params.stopNumber % params.stopCount == problem.stopAndTerminalNext.stop % params.stopCount then
				-- the alternative terminal the problem names, if any (line_problems.terminal_at)
				if terminalNumber == line_problems.terminal_at(problem, "next") then
					problemPrev = true
					problemTooltipPrev = problem.tooltip
				end
			end
		end
		for _i, problem in ipairs(problemsThis) do
			if params.stopNumber == problem.stopAndTerminalThis.stop then
				-- base: terminalNumber % stopCount == terminal % stopCount, always the preferred terminal
				if terminalNumber == line_problems.terminal_at(problem, "this") then
					problemThis = true
					problemTooltipThis = problem.tooltip
				end
			end
		end

		-- Why the line cannot use this terminal, if it cannot: greyed row, reasons in the tooltip.
		---@type string[]
		local reasons = {}
		local incompatible_text = incompatibility_text(incompatible[terminalData.number])
		if incompatible_text then reasons[#reasons + 1] = incompatible_text end
		if problemTooltipPrev then reasons[#reasons + 1] = problemTooltipPrev end
		if problemTooltipThis and problemTooltipThis ~= problemTooltipPrev then
			reasons[#reasons + 1] = problemTooltipThis
		end
		local reasonText = #reasons > 0 and table.concat(reasons, "\n") or nil
		local preferred = terminalData.current

		---@type react.TreeNodeId[]
		local floatingChildren = {}

		table.insert(floatingChildren, builtin.FloatingLayoutChild{
			h = -1,
			v = -1,
			item = builtin.Component{
				meta = {
					id = "uio.terminals.row." .. tostring(terminalData.number),
					class = "main, uio-terminal-row"
						.. (preferred and ", uio-terminal-preferred" or "")
						.. (reasonText and ", uio-terminal-unreachable" or ""),
					tooltip = reasonText,
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						builtin.Component{
							meta = {
								class = "problem-spacer-terminal",
							},
						},
						line_react_util.makeTerminalIndicator(terminalData.number, true),
						builtin.TextView {
							meta = {
								-- this text gets clipped when too long, so show the tooltip always
								tooltip = reasonText and (terminalText .. "\n" .. reasonText) or terminalText,
								class = (bubbleColor and "bubble, " or "") .. "font-scale-body, terminal-label-compact",
								styleSheet = bubbleColor and styleutil.makeStyle{
									color = gui_react_util.textColorForColor(api.type.Vec4f.new(bubbleColor, 1.0)),
									backgroundColor1 = {
										bubbleColor.x,
										bubbleColor.y,
										bubbleColor.z,
										1.0
									},
								} or nil,
							},
							text = terminalText,
						},
						gui_react_util.makeHorizontalSpacer(),
						builtin.TextView{
							meta = {
								class = "font-scale-body, terminal-length, " ..
									(terminalData.terminalLength == 0 and "invisible" or ""),
							},
							text = api.util.formatLength(terminalData.terminalLength),
						},
						usage_buttons(params, terminalData),
					},
				},
			},
		})

		table.insert(floatingChildren, builtin.FloatingLayoutChild{
			h = 0,
			v = -1,
			item = builtin.Component{
				meta = {
					class = "problem-spacer-terminal",
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Vertical,
					children = {
						problemPrev and builtin.ImageView{
							meta = {
								class = "terminal-problem, top",
								tooltip = problemTooltipPrev,
							},
							path = params.commonParams.iconPaths.problemArrow,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						} or builtin.Component{
							meta = {
								class = "terminal-problem",
							},
						},
						problemThis and builtin.ImageView{
							meta = {
								class = "terminal-problem, bottom",
								tooltip = problemTooltipThis,
							},
							path = params.commonParams.iconPaths.problemArrow,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						} or builtin.Component{
							meta = {
								class = "terminal-problem",
							},
						},
					},
				},
			}
		})

		table.insert(floatingChildren, builtin.FloatingLayoutChild{
			h = 0,
			v = -1,
			item = builtin.Component{
				meta = {
					class = "problem-terminal-length",
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						terminalData.hasOverlength and builtin.ImageView{
							meta = {
								class = "terminal-length-alert",
								tooltip = _("Terminal is too short for some vehicles."),
							},
							path = params.commonParams.iconPaths.problemAlert,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						} or nil,
					},
				},
			}
		})

		table.insert(children, builtin.FloatingLayout{
			children = floatingChildren,
		})
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			selectTerminalsHeader,
			builtin.ScrollArea{
				horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
				verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
				content = builtin.Component{
					layout = builtin.BoxLayout{
						orientation = builtin.type.Orientation.Vertical,
						children = children,
					},
				},
			},
		},
	}
end

-- The popover shows this recipe until it fails once, then the base popover for the rest of the
-- session (fallback.lua): a choice per render would mount one and then the other.
terminals.switch = fallback.switch("terminal popover")
local TerminalSelection = fallback.replacement(terminals.switch, BASE_NAME, render, nil, {
	render_base = function(params)
		local base = base_recipe or terminals.Vanilla
		return base(params)
	end,
})
terminals.TerminalSelection = TerminalSelection

-- The base popover, as a stand-in ---------------------------------------------------------------------

--- The label of a terminal as the base popover gives it: what it takes, a specialised cargo terminal
-- its cargo class's name and colour.
---@param terminalData uo.gui.terminals.TerminalData
---@return string text
---@return Vec3f? colour
function terminals.base_label(terminalData)
	if terminalData.isPassengerTerminal then
		return terminalData.isCargoTerminal and _("Passenger and Cargo") or _("Passenger"), nil
	end
	if terminalData.terminalSpecialization == "UNIVERSAL" then return _("All Cargo Types"), nil end
	local cargoClassId = api.res.cargoClassRep.getCargoClassId(terminalData.terminalSpecialization)
	if cargoClassId == -1 then return _("Passenger and Cargo"), nil end
	local specializationData = api.res.cargoClassRep.get(cargoClassId)
	return specializationData.name, specializationData.color
end

--- The base recipe TerminalSelection, converted to Lua line by line (line_manager_panel.tl), for where
-- it cannot be reached before the Line Manager opened a popover once: with Select Terminals off (or a
-- mod that comes first having the last word in it), the station and line window buttons show this,
-- as the Line Manager shows the base one. Under the base name, so the base stylesheet applies and mods
-- that swap the base popover by name take it too. Only the terminal reader is the shared one (the base
-- getter, its overlength check once per stop).
---@param params uo.gui.terminals.Params
---@return react.TreeNodeId?
local function render_vanilla(params)
	if not params.viaState or not params.viaState:old() then
		return nil
	end

	local terminalsState = engine_react_util.useStepState(function() return read_terminals(params) end)

	local selectTerminalsHeader = builtin.Component{
		meta = {
			class = "select-terminals-header",
		},
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.TextView{
					meta = {
						class = "font-scale-headline",
					},
					text = lang_util.format(_("Terminals for Stop {stopnumber}"), {
						stopnumber = lang_util.formatInt(params.stopNumber),
					}),
				},
			},
		},
	}

	local index2problems = params.index2problems or {}
	---@type react.TreeNodeId[]
	local children = {}
	for terminalNumber, terminalData in ipairs(terminalsState:old()) do
		local terminalText, bubbleColor = terminals.base_label(terminalData)

		local problemsPrev = index2problems[(params.stopNumber - 1) % params.stopCount]
		if not problemsPrev then
			problemsPrev = {}
		end
		local problemsThis = index2problems[params.stopNumber]
		if not problemsThis then
			problemsThis = {}
		end
		local problemPrev = false
		local problemThis = false
		local problemTooltipPrev = nil
		local problemTooltipThis = nil
		for _i, problem in ipairs(problemsPrev) do
			if params.stopNumber % params.stopCount == problem.stopAndTerminalNext.stop % params.stopCount then
				if terminalNumber == problem.stopAndTerminalNext.terminal then
					problemPrev = true
					problemTooltipPrev = problem.tooltip
				end
			end
		end
		for _i, problem in ipairs(problemsThis) do
			if params.stopNumber == problem.stopAndTerminalThis.stop then
				if terminalNumber % params.stopCount == problem.stopAndTerminalThis.terminal % params.stopCount then
					problemThis = true
					problemTooltipThis = problem.tooltip
				end
			end
		end

		local valueUnused = "Unused"
		local valueAlternative = "Alternative"
		local valueMain = "Main"

		---@param value string
		local onTerminalUsageValueChange = function(value)
			if value == valueAlternative then
				params.commonParams.selectAlternativeTerminal(
					params.stopNumber,
					terminalData.stationIndex1,
					terminalData.terminalIndex1,
					true
				)
			elseif value == valueMain then
				params.commonParams.changeMainTerminal(
					params.stopNumber,
					terminalData.stationIndex1,
					terminalData.terminalIndex1
				)
			else
				params.commonParams.selectAlternativeTerminal(
					params.stopNumber,
					terminalData.stationIndex1,
					terminalData.terminalIndex1,
					false
				)
			end
		end

		---@type react.TreeNodeId[]
		local terminalUsageItems = {
			builtin.ComboBoxItem{
				value = valueUnused,
				content = builtin.TextView{
					meta = {
						class = "font-scale-annotation",
					},
					text = _("Don't Use"),
				},
			},
			builtin.ComboBoxItem{
				value = valueAlternative,
				content = builtin.TextView{
					meta = {
						class = "font-scale-annotation",
					},
					text = _("Alternative"),
				},
			},
			builtin.ComboBoxItem{
				value = valueMain,
				content = builtin.TextView{
					meta = {
						class = "font-scale-annotation",
					},
					text = _("Preferred"),
				},
			},
		}

		-- (a hook per terminal, as the base declares it)
		---@type react.State<string>
		local terminalUsageValueState = engine_react_util.useStepState(function()
			if terminalData.current then
				return valueMain
			elseif terminalData.alternativeHere then
				return valueAlternative
			end
			return valueUnused
		end)

		---@type react.TreeNodeId[]
		local floatingChildren = {}

		table.insert(floatingChildren, builtin.FloatingLayoutChild{
			h = -1,
			v = -1,
			item = builtin.Component{
				meta = {
					class = "main",
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						builtin.Component{
							meta = {
								class = "problem-spacer-terminal",
							},
						},
						line_react_util.makeTerminalIndicator(terminalData.number, true),
						builtin.TextView {
							meta = {
								tooltip = terminalText, -- this text gets clipped when too long, so show the tooltip always
								class = (bubbleColor and "bubble, " or "") .. "font-scale-body, terminal-label-compact",
								styleSheet = bubbleColor and styleutil.makeStyle{
									color = gui_react_util.textColorForColor(api.type.Vec4f.new(bubbleColor, 1.0)),
									backgroundColor1 = {
										bubbleColor.x,
										bubbleColor.y,
										bubbleColor.z,
										1.0
									},
								} or nil,
							},
							text = terminalText,
						},
						gui_react_util.makeHorizontalSpacer(),
						builtin.TextView{
							meta = {
								class = "font-scale-body, terminal-length, " ..
									(terminalData.terminalLength == 0 and "invisible" or ""),
							},
							text = api.util.formatLength(terminalData.terminalLength),
						},
						builtin.ComboBox{
							meta = {
								tooltip = _("Set Terminal Usage"),
								enabled = terminalUsageValueState:old() ~= "Main",
							},
							value = terminalUsageValueState:old(),
							onValueChange = onTerminalUsageValueChange,
							items = terminalUsageItems,
						},
					},
				},
			},
		})

		table.insert(floatingChildren, builtin.FloatingLayoutChild{
			h = 0,
			v = -1,
			item = builtin.Component{
				meta = {
					class = "problem-spacer-terminal",
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Vertical,
					children = {
						problemPrev and builtin.ImageView{
							meta = {
								class = "terminal-problem, top",
								tooltip = problemTooltipPrev,
							},
							path = params.commonParams.iconPaths.problemArrow,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						} or builtin.Component{
							meta = {
								class = "terminal-problem",
							},
						},
						problemThis and builtin.ImageView{
							meta = {
								class = "terminal-problem, bottom",
								tooltip = problemTooltipThis,
							},
							path = params.commonParams.iconPaths.problemArrow,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						} or builtin.Component{
							meta = {
								class = "terminal-problem",
							},
						},
					},
				},
			}
		})

		table.insert(floatingChildren, builtin.FloatingLayoutChild{
			h = 0,
			v = -1,
			item = builtin.Component{
				meta = {
					class = "problem-terminal-length",
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						terminalData.hasOverlength and builtin.ImageView{
							meta = {
								class = "terminal-length-alert",
								tooltip = _("Terminal is too short for some vehicles."),
							},
							path = params.commonParams.iconPaths.problemAlert,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						} or nil,
					},
				},
			}
		})

		table.insert(children, builtin.FloatingLayout{
			children = floatingChildren,
		})
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			selectTerminalsHeader,
			builtin.ScrollArea{
				horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
				verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
				content = builtin.Component{
					layout = builtin.BoxLayout{
						orientation = builtin.type.Orientation.Vertical,
						children = children,
					},
				},
			},
		},
	}
end

-- A failure shows nothing for the rest of the session (fallback.lua), not a broken UI.
terminals.vanilla_switch = fallback.switch("base terminal popover stand-in")
---@type react.Recipe<uo.gui.terminals.Params>
terminals.Vanilla = fallback.replacement(terminals.vanilla_switch, BASE_NAME, render_vanilla, nil, {
	render_base = function() return nil end,
})

--- The base popover: the base recipe once the Line Manager handed it over, else its stand-in.
---@return react.Recipe<uo.gui.terminals.Params>
function terminals.base_popover()
	return base_recipe or terminals.Vanilla
end

-- Keeping the popover on the screen ------------------------------------------------------------------

-- Gap to the screen's edges in pixels, and room kept free for the game bar at the bottom, in parts of
-- the screen height (the game bar is about 6 % high at every resolution and text size, seen in game).
local EDGE = 8
local GAME_BAR = 0.07

--- Where a popover opened at (x, y) goes so that all of it lies on a `width` x `height` pixel screen.
-- Window positions and node positions are parts of the screen (0..1), the popover's top left corner
-- at (x, y). The game keeps a new window on the screen with the size it has before its content is laid
-- out, so a popover opened near the right or bottom edge reaches past it once the terminal rows fill it
-- (observed in game: opened at 0.9, its content spans 0.829..1.047 on a 21:9 screen). `rect` is its
-- content as laid out. It moves left and up only as far as needed. Returns nil if it already fits.
---@param x number
---@param y number
---@param rect { left: number, top: number, right: number, bottom: number }
---@param width number
---@param height number
---@return number? x
---@return number? y
function terminals.placement(x, y, rect, width, height)
	local edge_x, edge_y = EDGE / math.max(width, 1), EDGE / math.max(height, 1)
	local max_x = 1 - edge_x - (rect.right - rect.left)
	local max_y = 1 - GAME_BAR - (rect.bottom - rect.top)
	local left = math.min(x, rect.left)
	local top = math.min(y, rect.top)
	local new_x = math.max(edge_x, math.min(left, max_x))
	local new_y = math.max(edge_y, math.min(top, max_y))
	-- it fits while it is on the screen and above the game bar; a move leaves the gap EDGE
	if rect.right <= 1 and rect.bottom <= 1 - GAME_BAR + edge_y then return nil, nil end
	return new_x, new_y
end

--- The terminal popover as this mod opens it: the terminal selection, measured once it is laid out,
-- then moved onto the screen if it reaches past an edge (a stop button near the right or bottom edge,
-- a wide screen; the game does not keep windows on the screen). A recipe of its own name: mods that
-- swap the base popover by name (TerminalSelection) leave it alone where this mod comes first in the
-- mod list, and its parameters keep the shape of the base ones for mods that look at them.
---@type react.Recipe<uo.gui.terminals.Params>
terminals.Popover = react.RegisterRecipe("UioTerminalPopover",
---@param params uo.gui.terminals.Params
---@return react.TreeNodeId
function(params)
	local self_ref = react.useSelfRef()
	local steps = react.useRef(0)
	react.onStep(function()
		local step = steps:get() or 0
		if step > 2 then return end
		steps:set(step + 1)
		-- the layout is done after the first steps
		if step ~= 2 or params.place == nil then return end
		local ok, err = pcall(function()
			local node = self_ref:get()
			if node == nil then return end
			local top_left, bottom_right = node:getPosition(0, 0), node:getPosition(1, 1)
			params.place(top_left.x, top_left.y, bottom_right.x, bottom_right.y)
		end)
		if not ok then report("place", err) end
	end)
	return builtin.BoxLayout{ children = { TerminalSelection(params) } }
end)

--- Popover parameters with this recipe in place of the base terminal selection; other popovers' parameters
-- are returned unchanged. `recipe_name` is react.GetRecipeName (a parameter for the specs).
-- Other mods register popovers under the base name too (Terminal Selector, with parameters of its own),
-- so only a popover with the base parameters is taken over.
---@param p? game.gui.main.popover_react_util.PopoverWindowParam|react.RefFill the recipe's first argument
---@param recipe_name fun(recipe: function): string
---@return (game.gui.main.popover_react_util.PopoverWindowParam|react.RefFill)? # `p`, or a copy with this recipe
function terminals.swap(p, recipe_name)
	if type(p) ~= "table" or p.recipe == nil or p.recipe == TerminalSelection or p.recipe == terminals.Vanilla then
		return p
	end
	if recipe_name(p.recipe) ~= BASE_NAME then return p end
	local params = p.params
	if type(params) ~= "table" or params.viaState == nil or params.commonParams == nil then return p end
	base_recipe = p.recipe
	local copy = guard.shallow_copy(p)
	copy.recipe = terminals.Popover
	return copy
end

-- Popover outside the Line Manager ----------------------------------------------------------------

local ICON = "::/gui/line_vehicle_mgmt/icons/indicator_terminal.tga" -- the Line Manager's terminal icon
---@type uo.gui.terminals.IconPaths
local ICON_PATHS = { -- the entries of the Line Manager's iconPaths the popover uses
	problemAlert = "::/gui/statistics/icons/alert.tga",
	problemArrow = "::/gui/line_vehicle_mgmt/icons/special_arrow_down.tga",
}

---@param a Engine.Revision
---@param b Engine.Revision
---@return boolean
local function same_revision(a, b)
	return a.num[1] == b.num[1] and a.num[2] == b.num[2] and a.num[3] == b.num[3]
end

--- Line state of `line` for the popover: old() is the line as the Line Manager keeps it, read again
-- when the line changes and the same table until then (as the base state is between two steps, which
-- mods editing it before a change rely on).
---@param line Engine.Entity
---@param read fun(line: Engine.Entity): game.gui.line_vehicle_mgmt.line.ReactLine
---@param revision fun(line: Engine.Entity): Engine.Revision
---@return uo.gui.terminals.LineState
function terminals.line_state(line, read, revision)
	---@type game.gui.line_vehicle_mgmt.line.ReactLine?, Engine.Revision?
	local cached, cached_revision
	return {
		old = function()
			if not api.engine.entityExists(line) then return nil end
			local current = revision(line)
			if cached == nil or cached_revision == nil or not same_revision(cached_revision, current) then
				cached, cached_revision = read(line), current
			end
			return cached
		end,
		reset = function() cached = nil end,
	}
end

--- Sends `react_line` as the update of its line, as the Line Manager does on a change.
---@param react_line game.gui.line_vehicle_mgmt.line.ReactLine
local function commit(react_line)
	local line = react_line.entityAndRevision.entity
	local component = api.type.Line.new()
	component.stops = line_util.autoAssignTerminals(line, react_line.path)
	component.customFilters = react_line.customFilters
	component.reservationPriority = react_line.reservationPriority
	api.cmd.sendCommand(api.cmd.makeLineUpdateCmd(line, component), function(_result, success)
		if not success then report("line update", "rejected") end
	end)
end

--- The Line Manager's terminal changes on a line state (manager_window.tl, commonParams).
---@param line_state uo.gui.terminals.LineState
---@param send fun(react_line: game.gui.line_vehicle_mgmt.line.ReactLine)
---@return uo.gui.terminals.CommonParams
function terminals.common_params(line_state, send)
	---@param modify fun(react_line: game.gui.line_vehicle_mgmt.line.ReactLine)
	local function change(modify)
		local react_line = line_state.old()
		if not react_line then return end
		react_line = table_util.copy(react_line)
		modify(react_line)
		line_state.reset()
		send(react_line)
	end
	return {
		lineState = { old = function(_self) return line_state.old() end },
		iconPaths = ICON_PATHS,
		changeMainTerminal = function(stopNumber, stationIndex1, terminalIndex1)
			change(function(react_line)
				react_line.path[stopNumber].stop.station1 = stationIndex1
				react_line.path[stopNumber].stop.terminal1 = terminalIndex1
			end)
		end,
		selectAlternativeTerminal = function(stopNumber, stationIndex1, terminalIndex1, add)
			change(function(react_line)
				local stop = react_line.path[stopNumber].stop
				---@cast stop -nil -- the popover's stop number is a stop, not a waypoint
				---@type StationTerminal[]
				local alternatives = {}
				for _i, v in ipairs(stop.alternativeTerminals) do
					if v.station ~= stationIndex1 - 1 or v.terminal ~= terminalIndex1 - 1 then
						alternatives[#alternatives + 1] = api.type.StationTerminal.new(v.station, v.terminal)
					end
				end
				if add then
					alternatives[#alternatives + 1] = api.type.StationTerminal.new(stationIndex1 - 1, terminalIndex1 - 1)
				end
				stop.alternativeTerminals = alternatives
			end)
		end,
	}
end

--- Number of the stop `stop_index0` in `path` (stops and waypoints, as the Line Manager counts).
---@param path game.gui.line_vehicle_mgmt.line.ReactVia[]
---@param stop_index0 integer
---@return integer?
function terminals.stop_number(path, stop_index0)
	local stops = 0
	for number, via in ipairs(path) do
		if via.stop then
			if stops == stop_index0 then return number end
			stops = stops + 1
		end
	end
	return nil
end

--- Popover parameters for stop `stop_index0` of `line`, in the shape of the Line Manager's.
---@param line Engine.Entity
---@param stop_index0 integer
---@return uo.gui.terminals.Params?
function terminals.popover_params(line, stop_index0)
	local line_state = terminals.line_state(line, line_util.getReactLineFromGameState, api.engine.getRevision)
	local react_line = line_state.old()
	if not react_line then return nil end
	local stop_number = terminals.stop_number(react_line.path, stop_index0)
	if not stop_number then return nil end
	return {
		commonParams = terminals.common_params(line_state, commit),
		viaState = {
			old = function(_self)
				local current = line_state.old()
				return current and current.path
			end,
		},
		lineEntity = line,
		stopNumber = stop_number,
		stopIndex = stop_index0,
		stopCount = #react_line.path,
		index2problems = {},
	}
end

-- Loaded on the first click, not with this file: it loads game.tl and with it the menu pages, whose
-- require paths (a doubled slash before engine_react_util.tl) the game's mod validator reports as errors.
local GAME_REACT_GLOBALS = "::/gui/main/game_react_globals.tl"

-- A new window key for each popover, so it opens at the button and not where the previous one was
-- (as popover_react_util does).
local popovers_opened = 0

--- Opens the terminal popover of stop `stop_index0` of `line` at `position`.
---@param line Engine.Entity
---@param stop_index0 integer
---@param position Vec2f
---@param title string
function terminals.open(line, stop_index0, position, title)
	local params = terminals.popover_params(line, stop_index0)
	-- required by a variable path, which the type checker cannot follow
	local game_react_globals = require(GAME_REACT_GLOBALS) --[[@as game.gui.main.game_react_globals]]
	local windows = game_react_globals.getDefaultWindowApi()
	if not params or not windows then
		report("open", "no popover for line " .. tostring(line) .. " stop " .. tostring(stop_index0)
			.. (windows and "" or " (no window api)"))
		return
	end
	-- Where the popover feature is off, or a mod that comes first in the mod list wraps the popover
	-- (Easy Terminal Assignment), it is the base popover, as the Line Manager opens it: such a mod swaps
	-- it by name for its own.
	local own = priority.active("terminals") and not priority.outranked("terminals")
	local recipe = own and terminals.Popover or terminals.base_popover()
	if not own then
		debugPrint("[ui_overhaul] terminal popover: the game's own", base_recipe and "" or " (its stand-in)",
			" (Select Terminals ", priority.active("terminals") and "has a mod that comes first" or "is off", ")")
	end
	---@param x number
	---@param y number
	local function show(x, y)
		popovers_opened = popovers_opened + 1
		windows.removeAllWindows(popover_react_util.PopoverWindow)
		windows.addWindow(popover_react_util.PopoverWindow, "uio.terminals." .. popovers_opened, {
			onClose = function() windows.removeAllWindows(popover_react_util.PopoverWindow) end,
			x = x,
			y = y,
			windowTitle = title,
			windowClass = "select-terminal, management",
			recipe = recipe,
			params = params,
		})
	end
	---@param left number
	---@param top number
	---@param right number
	---@param bottom number
	local function place(left, top, right, bottom)
		params.place = nil -- once
		local screen = api.gui.camera.getSize()
		local rect = { left = left, top = top, right = right, bottom = bottom }
		local x, y = terminals.placement(position.x, position.y, rect, screen.x, screen.y)
		if x and y then
			debugPrint(string.format("[ui_overhaul] terminal popover moved onto the screen: %.3f,%.3f -> %.3f,%.3f"
				.. " (content %.3f..%.3f x %.3f..%.3f)", position.x, position.y, x, y, left, right, top, bottom))
			-- the moved popover is measured once more, for the log
			params.place = function(l, t, r, b)
				params.place = nil
				local fits = terminals.placement(x, y, { left = l, top = t, right = r, bottom = b }, screen.x, screen.y) == nil
				debugPrint(string.format("[ui_overhaul] terminal popover now at content %.3f..%.3f x %.3f..%.3f: %s",
					l, r, t, b, fits and "on the screen" or "still past an edge"))
			end
			show(x, y)
		end
	end
	params.place = place
	show(position.x, position.y)
end

--- Button that opens the terminal popover of stop `stopIndex0` (0-based, without waypoints) of `line`.
-- `id`: component id of the button, unique among all open windows.
---@type react.Recipe<uo.gui.terminals.TerminalButtonParams>
terminals.TerminalButton = react.RegisterRecipe("UioTerminalButton",
---@param params uo.gui.terminals.TerminalButtonParams
---@return react.TreeNodeId
function(params)
	local self_ref = react.useSelfRef()
	local title = _("Select Terminals")
	return builtin.BoxLayout{
		children = {
			builtin.Button{
				meta = { class = "uio-terminal-button", id = params.id,
					tooltip = params.problem and params.problem .. "\n\n" .. title or title },
				content = builtin.ImageView{ path = ICON, scaling = builtin.type.ImageViewScaling.AutoFit },
				onClick = function()
					local position = self_ref:get():getPosition(1.0, 0.0)
					local ok, err = pcall(terminals.open, params.line, params.stopIndex0, position, title)
					if not ok then report("open", err) end
				end,
			},
		},
	}
end)

--- Wraps `previous` (the PopoverWindowContent function: the base recipe, or another mod's wrapper).
---@param previous react.Recipe<game.gui.main.popover_react_util.PopoverWindowParam>
---@return react.Recipe<game.gui.main.popover_react_util.PopoverWindowParam>
function terminals.wrap(previous)
	-- called as the recipe is: (params) or (ref, params)
	---@param p? game.gui.main.popover_react_util.PopoverWindowParam|react.RefFill
	---@param ... game.gui.main.popover_react_util.PopoverWindowParam
	---@return react.TreeNodeId
	return function(p, ...)
		local ok, swapped = pcall(terminals.swap, p, react.GetRecipeName)
		if not ok then
			report("swap", swapped)
			swapped = p
		end
		return previous(swapped, ...)
	end
end

--- Called by installer.lua before the UI starts.
---@param _replacement_api react.ReplacementApi
function terminals.install(_replacement_api)
	priority.chain(popover_react_util, "PopoverWindowContent", terminals.wrap)
	debugPrint("[ui_overhaul] terminal usage buttons installed")
end

return terminals
