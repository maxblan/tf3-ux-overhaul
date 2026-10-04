--- Path problems of a line, per stop and terminal, as the Line Manager's stop list computes them
-- (gui/line_vehicle_mgmt/line_manager_panel.tl, index2problems): the terminal popover marks the
-- terminal a problem starts or ends at. The Line Manager hands the popover its own list; outside it
-- (station and line window) the mod builds the same list from a plain copy of
-- api.engine.util.line.getDetailedLineProblems. Pure Lua: the GUI turns `kind` into the base text.
-- @module ui_overhaul.core.line_problems
local line_problems = {}

--- LineUtil.RelaxationType (gui/line_vehicle_mgmt/line_util.d.tl).
---@alias uo.core.line_problems.Reason "Catenary"|"Road"|"Train"|"TramLanes"|"TramTrack"

---@alias uo.core.line_problems.Kind
---| "duplicate"
---| "incompatible"
---| "no_path"
---| "from_alternative"
---| "from_alternative_to_alternative"
---| "to_alternative"

--- A stop or waypoint of the line, in line order.
---@class uo.core.line_problems.Stop
---@field name? string the station group's name (stops only)
---@field terminal0? integer flat 0-based terminal index in the station group, line_problems.WAYPOINT for waypoints
---@field stopIndex? integer 1-based index among the stops (stops only)

--- The alternative terminal a path starts or ends at: { terminal0, reason }.
---@class uo.core.line_problems.Alternative
---@field [1] integer flat 0-based terminal index
---@field [2] uo.core.line_problems.Reason?

--- Plain copy of a getDetailedLineProblems stop state.
---@class uo.core.line_problems.State
---@field noPath? boolean
---@field duplicate? boolean
---@field incompatible? boolean
---@field reason? uo.core.line_problems.Reason
---@field fromAlternative? uo.core.line_problems.Alternative
---@field toAlternative? uo.core.line_problems.Alternative

---@class uo.core.line_problems.StopAndTerminal
---@field stop integer
---@field terminal integer 1-based

---@class uo.core.line_problems.Params
---@field origin? string
---@field destination? string
---@field terminalOrigin integer 1-based
---@field terminalDestination integer 1-based
---@field originIsWaypoint boolean
---@field destinationIsWaypoint boolean
---@field reason? uo.core.line_problems.Reason

---@class uo.core.line_problems.Problem
---@field stopAndTerminalThis uo.core.line_problems.StopAndTerminal
---@field stopAndTerminalNext uo.core.line_problems.StopAndTerminal
---@field kind uo.core.line_problems.Kind
---@field params uo.core.line_problems.Params
---@field tooltip? string set by gui/terminals.lua, as in the Line Manager's own list

--- What a terminal serves or a line's vehicles carry (see line_problems.incompatibility).
---@class uo.core.line_problems.Needs
---@field carriers table<Carrier, boolean> carrier -> true
---@field passengers? boolean
---@field cargo? boolean

--- A Line Manager path entry (Line.ReactVia, gui/line_vehicle_mgmt/line.d.tl): a stop or a waypoint.
---@class uo.core.line_problems.Via
---@field stop? table the stop's terminal (Line.ReactTerminal), nil for a waypoint

---@alias uo.core.line_problems.Incompatibility "carrier"|"passengers_only"|"cargo_only"

--- Terminal number of a waypoint in `stops` (base: waypointMagicNumber).
line_problems.WAYPOINT = -1

-- Kind of a stop state's path problem, or nil.
---@param state uo.core.line_problems.State
---@return uo.core.line_problems.Kind?
local function path_kind(state)
	if state.noPath then return "no_path" end
	if state.fromAlternative then
		return state.toAlternative and "from_alternative_to_alternative" or "from_alternative"
	end
	if state.toAlternative then return "to_alternative" end
	return nil
end

--- Kind of a stop state's problem, or nil: "duplicate", "incompatible", "no_path", "from_alternative",
-- "from_alternative_to_alternative" or "to_alternative" (base order of the checks).
---@param state uo.core.line_problems.State
---@return uo.core.line_problems.Kind?
function line_problems.kind(state)
	if state.duplicate then return "duplicate" end
	if state.incompatible then return "incompatible" end
	return path_kind(state)
end

---@param kind uo.core.line_problems.Kind?
---@return boolean
local function is_path_kind(kind)
	return kind ~= nil and kind ~= "duplicate" and kind ~= "incompatible"
end

--- The Line Manager's index2problems from plain data:
--   stops[i] = { name, terminal0 }   for every stop and waypoint in line order (terminal0: flat
--                                     0-based terminal index in the station group, WAYPOINT for waypoints)
--   segments = { { state, ... }, ... } the getDetailedLineProblems result, each state a table with
--                noPath, fromAlternative = { terminal0, reason }, toAlternative = { terminal0, reason },
--                duplicate, incompatible, reason (reason: a relaxation type or nil)
-- Returns index -> { problem } with index 0 a copy of the last index (wrap around), each problem
-- { stopAndTerminalThis = { stop, terminal }, stopAndTerminalNext = { stop, terminal }, kind, params },
-- terminals 1-based. `params` holds origin, destination, terminalOrigin, terminalDestination (numbers,
-- 1-based), reason, and the flags originIsWaypoint / destinationIsWaypoint.
---@param stops uo.core.line_problems.Stop[]
---@param segments? uo.core.line_problems.State[][]
---@return table<integer, uo.core.line_problems.Problem[]>
function line_problems.index2problems(stops, segments)
	local count = #stops
	---@param index integer
	---@return uo.core.line_problems.Stop
	local function stop(index)
		if index == 0 then return stops[count] or {} end
		return stops[index] or {}
	end

	local result = {} ---@type table<integer, uo.core.line_problems.Problem[]>
	local index = 0
	for _i, segment in ipairs(segments or {}) do
		for _j, state in ipairs(segment) do
			index = index + 1
			result[index] = {}
			-- a stop that is incompatible and has no path gets both problems (the base shows the first)
			local kinds = {} ---@type uo.core.line_problems.Kind[]
			local primary = line_problems.kind(state)
			if primary then kinds[1] = primary end
			if primary and not is_path_kind(primary) and path_kind(state) then kinds[2] = path_kind(state) end
			if count > 0 then
				local next_index = (index + 1) % count ---@type integer
				local this_stop, next_stop = stop(index), stop(next_index)
				local terminal_this = this_stop.terminal0 or 0
				local terminal_next = next_stop.terminal0 or 0
				for _k, kind in ipairs(kinds) do
					---@type uo.core.line_problems.Params
					local params = {
						origin = this_stop.name,
						destination = next_stop.name,
						terminalOrigin = terminal_this + 1,
						terminalDestination = terminal_next + 1,
						originIsWaypoint = terminal_this == line_problems.WAYPOINT,
						destinationIsWaypoint = terminal_next == line_problems.WAYPOINT,
					}
					if state.noPath then
						params.reason = state.reason
					elseif state.fromAlternative then
						params.terminalOrigin = state.fromAlternative[1] + 1
						params.reason = state.fromAlternative[2]
						if state.toAlternative then params.terminalDestination = state.toAlternative[1] + 1 end
					elseif state.toAlternative then
						params.terminalDestination = state.toAlternative[1] + 1
						params.reason = state.toAlternative[2]
					end
					---@type uo.core.line_problems.Problem
					local problem = {
						stopAndTerminalThis = { stop = index, terminal = terminal_this + 1 },
						stopAndTerminalNext = { stop = next_index, terminal = terminal_next + 1 },
						kind = kind,
						params = params,
					}
					table.insert(result[index], problem)
				end
			end
		end
	end
	result[0] = {}
	for _i, problem in ipairs(result[index] or {}) do table.insert(result[0], problem) end
	return result
end

--- Problems that keep vehicles from reaching stop `stop_index` (1-based, without waypoints): a path
-- problem on any segment between the stop before it and this stop (waypoints in between included,
-- wrapping from the last stop), and a duplicate or incompatible stop at the stop itself. `stops` as
-- for index2problems, each stop with its `stopIndex`. Returns a list of problems (possibly empty).
---@param stops uo.core.line_problems.Stop[]
---@param segments? uo.core.line_problems.State[][]
---@param stop_index integer
---@return uo.core.line_problems.Problem[]
function line_problems.stop_problems(stops, segments, stop_index)
	local count = #stops
	local flat ---@type integer?
	for index, entry in ipairs(stops) do
		if entry.stopIndex == stop_index then flat = index end
	end
	if not flat then return {} end
	local all = line_problems.index2problems(stops, segments)
	local result = {} ---@type uo.core.line_problems.Problem[]
	-- walk back from the entry before this stop to the stop before it (inclusive)
	local index = flat
	for _i = 1, count - 1 do
		index = index - 1
		if index < 1 then index = count end
		for _j, problem in ipairs(all[index] or {}) do
			if is_path_kind(problem.kind) then result[#result + 1] = problem end
		end
		if stops[index].stopIndex then break end
	end
	for _i, problem in ipairs(all[flat] or {}) do
		if not is_path_kind(problem.kind) then result[#result + 1] = problem end
	end
	return result
end

--- The stops before and after insert position `insert_at` of a Line Manager path (the new stop goes
-- after path[insert_at]; nil = at the end), skipping waypoints (entries without `stop`) and wrapping
-- around. Returns before, after (path entries), nil for an empty path.
---@generic V: uo.core.line_problems.Via
---@param path V[]
---@param insert_at? integer
---@return V? before
---@return V? after
function line_problems.neighbours(path, insert_at)
	local count = #path
	if count == 0 then return nil, nil end
	insert_at = insert_at or count
	local before, after ---@type uo.core.line_problems.Via?, uo.core.line_problems.Via?
	for i = 0, count - 1 do
		local via = path[((insert_at - 1 - i) % count) + 1] ---@type uo.core.line_problems.Via
		if via.stop then before = via break end
	end
	for i = 1, count do
		local via = path[((insert_at - 1 + i) % count) + 1] ---@type uo.core.line_problems.Via
		if via.stop then after = via break end
	end
	return before, after
end

--- Why vehicles of a line cannot use a terminal, or nil. `terminal` = { carriers = { carrier = true },
-- passengers = bool, cargo = bool }; `line` = { carriers = { carrier = true } (empty: unknown),
-- passengers = bool, cargo = bool } (what the line's vehicles carry; both false: unknown).
-- Returns "carrier", "passengers_only" (a passenger terminal, the line carries only cargo) or
-- "cargo_only" (a cargo terminal, the line carries only passengers).
---@param terminal uo.core.line_problems.Needs
---@param line uo.core.line_problems.Needs
---@return uo.core.line_problems.Incompatibility?
function line_problems.incompatibility(terminal, line)
	if next(line.carriers) ~= nil and next(terminal.carriers) ~= nil then
		local shared = false
		for carrier in pairs(terminal.carriers) do
			if line.carriers[carrier] then shared = true end
		end
		if not shared then return "carrier" end
	end
	if terminal.passengers and not terminal.cargo and line.cargo and not line.passengers then
		return "passengers_only"
	end
	if terminal.cargo and not terminal.passengers and line.passengers and not line.cargo then
		return "cargo_only"
	end
	return nil
end

return line_problems
