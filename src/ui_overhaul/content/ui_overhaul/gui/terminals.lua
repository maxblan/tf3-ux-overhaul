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
-- wrapper hands it this recipe instead of the base one. Other mods that replace the recipe
-- PopoverWindowContent (e.g. Auto Assign Terminals) still see the same parameters. If rendering fails,
-- the base popover is shown. Installed by terminals.script.lua.
--
-- TerminalButton opens the same popover outside the Line Manager (station window, line window). Its
-- parameters have the shape of the Line Manager's, with the line read from the game and each change
-- sent as a line update, so a mod that swaps the base popover by name (Easy Terminal Assignment) shows
-- its own popover here too.
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

local BASE_NAME = "TerminalSelection"

-- Button order and values as in the base drop-down list.
---@type uo.gui.terminals.Usage[]
local USAGES = { "Unused", "Alternative", "Main" }

-- The base recipe, taken from the first terminal popover; shown if this one fails.
---@type react.Recipe<uo.gui.terminals.Params>?
local base_recipe

---@type table<string, true>
local reported = {}
---@param key string
---@param err any the error value of a pcall
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] terminal selection: ", key, ": ", tostring(err))
end

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

---@return number
local function clock()
	local ok, t = pcall(os.clock)
	return ok and t or 0
end

-- The cached results of `line`'s stop `stop_index0` (number -> result or false), fresh if needed.
---@param line Engine.Entity
---@param stop_index0 integer
---@return table<integer, uo.gui.terminals.Issue|false>
local function reach_entry(line, stop_index0)
	local now = clock()
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
				if terminalNumber == problem.stopAndTerminalNext.terminal then
					problemPrev = true
					problemTooltipPrev = problem.tooltip
				end
			end
		end
		for _i, problem in ipairs(problemsThis) do
			if params.stopNumber == problem.stopAndTerminalThis.stop then
				-- base: terminalNumber % stopCount == terminal % stopCount
				if terminalNumber == problem.stopAndTerminalThis.terminal then
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
	render_base = function(params) return base_recipe and base_recipe(params) or nil end,
})
terminals.TerminalSelection = TerminalSelection

--- Popover parameters with this recipe in place of the base terminal selection; other popovers' parameters
-- are returned unchanged. `recipe_name` is react.GetRecipeName (a parameter for the specs).
-- Other mods register popovers under the base name too (Terminal Selector, with parameters of its own),
-- so only a popover with the base parameters is taken over.
---@param p? game.gui.main.popover_react_util.PopoverWindowParam|react.RefFill the recipe's first argument
---@param recipe_name fun(recipe: function): string
---@return (game.gui.main.popover_react_util.PopoverWindowParam|react.RefFill)? # `p`, or a copy with this recipe
function terminals.swap(p, recipe_name)
	if type(p) ~= "table" or p.recipe == nil or p.recipe == TerminalSelection then return p end
	if recipe_name(p.recipe) ~= BASE_NAME then return p end
	local params = p.params
	if type(params) ~= "table" or params.viaState == nil or params.commonParams == nil then return p end
	base_recipe = p.recipe
	-- a shallow copy of every field, whatever their types (hence any)
	---@type table<string, any>
	local copy = {}
	for k, v in pairs(p --[[@as table<string, any>]]) do copy[k] = v end
	---@cast copy game.gui.main.popover_react_util.PopoverWindowParam -- p's fields, so the same shape
	copy.recipe = TerminalSelection
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
	if not params or not windows then return end
	popovers_opened = popovers_opened + 1
	windows.removeAllWindows(popover_react_util.PopoverWindow)
	windows.addWindow(popover_react_util.PopoverWindow, "uio.terminals." .. popovers_opened, {
		onClose = function() windows.removeAllWindows(popover_react_util.PopoverWindow) end,
		x = position.x,
		y = position.y,
		windowTitle = title,
		windowClass = "select-terminal, management",
		recipe = TerminalSelection,
		params = params,
	})
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
				meta = { class = "uio-terminal-button", tooltip = title, id = params.id },
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

--- Called from the react-replacement-config before the UI starts.
---@param _replacement_api react.ReplacementApi
function terminals.install(_replacement_api)
	local previous = popover_react_util.PopoverWindowContent
	if previous == nil then error("popover_react_util.PopoverWindowContent not found") end
	popover_react_util.PopoverWindowContent = terminals.wrap(previous)
	debugPrint("[ui_overhaul] terminal usage buttons installed")
end

return terminals
