--- Path problems of a line, per stop and terminal, as the Line Manager's stop list computes them
-- (gui/line_vehicle_mgmt/line_manager_panel.tl, index2problems): the terminal popover marks the
-- terminal a problem starts or ends at. The Line Manager hands the popover its own list; outside it
-- (station and line window) the mod builds the same list from a plain copy of
-- api.engine.util.line.getDetailedLineProblems. Pure Lua: the GUI turns `kind` into the base text.
-- @module ui_overhaul.core.line_problems
local line_problems = {}

--- Terminal number of a waypoint in `stops` (base: waypointMagicNumber).
line_problems.WAYPOINT = -1

--- Kind of a stop state's problem, or nil: "duplicate", "incompatible", "no_path", "from_alternative",
-- "from_alternative_to_alternative" or "to_alternative" (base order of the checks).
function line_problems.kind(state)
	if not (state.noPath or state.fromAlternative or state.toAlternative or state.duplicate or state.incompatible) then
		return nil
	end
	if state.duplicate then return "duplicate" end
	if state.incompatible then return "incompatible" end
	if state.noPath then return "no_path" end
	if state.fromAlternative then
		return state.toAlternative and "from_alternative_to_alternative" or "from_alternative"
	end
	return "to_alternative"
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
function line_problems.index2problems(stops, segments)
	local count = #stops
	local function stop(index)
		if index == 0 then return stops[count] or {} end
		return stops[index] or {}
	end

	local result = {}
	local index = 0
	for _i, segment in ipairs(segments or {}) do
		for _j, state in ipairs(segment) do
			index = index + 1
			result[index] = {}
			local kind = line_problems.kind(state)
			if kind and count > 0 then
				local next_index = (index + 1) % count
				local this_stop, next_stop = stop(index), stop(next_index)
				local terminal_this = this_stop.terminal0 or 0
				local terminal_next = next_stop.terminal0 or 0
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
				table.insert(result[index], {
					stopAndTerminalThis = { stop = index, terminal = terminal_this + 1 },
					stopAndTerminalNext = { stop = next_index, terminal = terminal_next + 1 },
					kind = kind,
					params = params,
				})
			end
		end
	end
	result[0] = {}
	for _i, problem in ipairs(result[index] or {}) do table.insert(result[0], problem) end
	return result
end

--- Why vehicles of a line cannot use a terminal, or nil. `terminal` = { carriers = { carrier = true },
-- passengers = bool, cargo = bool }; `line` = { carriers = { carrier = true } (empty: unknown),
-- passengers = bool, cargo = bool } (what the line's vehicles carry; both false: unknown).
-- Returns "carrier", "passengers_only" (a passenger terminal, the line carries only cargo) or
-- "cargo_only" (a cargo terminal, the line carries only passengers).
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
