--- Station window, Terminals list: a "Select Terminals" button on every line stop, at the right of
-- the row before the waiting count. It opens the Line Manager's terminal popover for that stop
-- (terminals.TerminalButton), so the terminals of a line can be set from the station. A line whose
-- vehicles cannot reach this stop (no path into it, an incompatible or doubled stop) gets the
-- statistics alert icon in front of the button, and the game's problem text heads the button's tooltip.
--
-- The list (TerminalStops, gui/entity_window/station_group/station_group.tl) is file-local and cannot
-- be replaced; replacing the whole station window would clash with every other mod that does. Two
-- calls the list makes are wrapped instead, both looked up when they run:
--   * orderedPairs (global), which walks the list's lines: it records the line of each row;
--   * gui_react_util.makeHorizontalSpacer, called once in each row before the waiting count (once per
--     line with one stop here, once per stop otherwise): the spacer is returned with the button in it.
-- Both act only while the recipe TerminalStops renders, and only while the station window is the base
-- one: a mod that replaces it (Terminal Selector) brings its own buttons. On any error the row stays
-- as it is and one line is logged. Installed by installer.lua.
-- @module ui_overhaul.gui.station_terminals
local builtin = require("::/gui/main/builtin.lua")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local react = require("::/gui/main/react.lua")
local station_group = require("::/gui/entity_window/station_group/station_group.tl")
local terminals = require("ui_overhaul_1::/ui_overhaul/gui/terminals.lua")
local line_problems = require("/ui_overhaul/core/line_problems.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")
local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")

---@class uo.gui.station_terminals
local station_terminals = {}

---A line's stop at this station in the base list (station_group.tl StopAndQualityState), the field used.
---@class uo.gui.station_terminals.StopEntry
---@field stopIndex0 integer

-- orderedPairs walks any table, so its keys and values are any
---@alias uo.gui.station_terminals.Iterator fun(t: table, k?: any): any, any
---@alias uo.gui.station_terminals.OrderedPairs fun(t: table, ...: any): uo.gui.station_terminals.Iterator, table, nil

---@class uo.gui.station_terminals.ProblemsEntry
---@field time number
---@field data? uo.gui.terminals.ProblemData

local LIST_RECIPE = "TerminalStops"

local report = guard.reporter("station terminal buttons: ")

--- True while the base list renders: the current recipe is `LIST_RECIPE` and no mod replaced the
-- station window. `current_recipe` and `replaced` are parameters for the specs.
---@param current_recipe fun(): string
---@param replaced fun(): boolean
---@return boolean
function station_terminals.in_base_list(current_recipe, replaced)
	local ok, name = pcall(current_recipe)
	return ok and name == LIST_RECIPE and not replaced()
end

---@return string
local function current_recipe()
	return react.getCurrentRecipeName()
end

---@return boolean
local function station_window_replaced()
	local id = react.GetRecipeId(station_group)
	return id ~= nil and _react.recipeReplace[id] ~= nil
end

--- Walk state of one list render: the line of the current row and how many rows of it were made.
--- `row(stops)` returns the stop (0-based) of the next spacer of the line with `stops` here.
---@return uo.gui.station_terminals.Walk
function station_terminals.new_walk()
	---Walk state of one list render.
	---@class uo.gui.station_terminals.Walk
	---@field line? Engine.Entity the line of the current row
	---@field stops? uo.gui.station_terminals.StopEntry[] its stops at this station
	---@field rows? integer rows of it made so far
	local walk = {}
	---@param line Engine.Entity
	---@param stops uo.gui.station_terminals.StopEntry[]
	function walk.enter(line, stops)
		walk.line, walk.stops, walk.rows = line, stops, 0
	end
	---@return integer?
	function walk.next_stop()
		if walk.line == nil or type(walk.stops) ~= "table" then return nil end
		walk.rows = walk.rows + 1
		local entry = #walk.stops == 1 and walk.stops[1] or walk.stops[walk.rows]
		return entry and entry.stopIndex0
	end
	function walk.leave()
		walk.line, walk.stops, walk.rows = nil, nil, 0
	end
	return walk
end

local walk = station_terminals.new_walk()

--- Component id of the button of stop `stop_index0` of `line` (a line stops at a station once per stop).
---@param line Engine.Entity
---@param stop_index0 integer
---@return string
function station_terminals.button_id(line, stop_index0)
	return "uio.terminals.station." .. tostring(line) .. "." .. tostring(stop_index0)
end

--- orderedPairs that records each line it yields while the list renders.
---@param previous uo.gui.station_terminals.OrderedPairs
---@param in_list fun(): boolean
---@return uo.gui.station_terminals.OrderedPairs
function station_terminals.wrap_ordered_pairs(previous, in_list)
	return function(t, ...)
		local iterator, state, initial = previous(t, ...)
		local ok, active = pcall(in_list)
		if not ok or not active then return iterator, state, initial end
		walk.leave()
		return function(s, key)
			local next_key, value = iterator(s, key)
			if next_key == nil then walk.leave() else walk.enter(next_key, value) end
			return next_key, value
		end, state, initial
	end
end

-- Problems per line, read at most every two seconds (the list renders often, the search is costly).
---@type table<Engine.Entity, uo.gui.station_terminals.ProblemsEntry>
local problems_cache = {}
local PROBLEMS_SECONDS = 2

local PRUNE_SECONDS = 60 -- lines not looked at for this long are dropped from the cache

---@param line Engine.Entity
---@param stop_index0 integer
---@return string?
local function stop_problem_text(line, stop_index0)
	local now = guard.clock() -- nil without a clock: then nothing is cached
	local entry = problems_cache[line]
	if not entry or not now or now - entry.time > PROBLEMS_SECONDS then
		for key, old in pairs(problems_cache) do
			if not now or now - old.time > PRUNE_SECONDS then problems_cache[key] = nil end
		end
		local ok, data = pcall(terminals.read_problems, line)
		entry = { time = now or 0, data = ok and data or nil }
		problems_cache[line] = entry
	end
	if not entry.data then return nil end
	---@type string[]
	local texts = {}
	for _i, problem in ipairs(line_problems.stop_problems(entry.data.stops, entry.data.segments, stop_index0 + 1)) do
		texts[#texts + 1] = terminals.problem_text(problem)
	end
	return #texts > 0 and table.concat(texts, "\n") or nil
end

--- The spacer, with the button of the current row's stop at its right while the list renders.
-- `...: any`: whatever a caller passes, handed on untouched (the base passes nothing)
---@param previous fun(...: any): react.TreeNodeId
---@param in_list fun(): boolean
---@param button react.Recipe<uo.gui.terminals.TerminalButtonParams>
---@return fun(...: any): react.TreeNodeId
function station_terminals.wrap_spacer(previous, in_list, button)
	return function(...)
		local spacer = previous(...)
		local ok, result = pcall(function()
			if walk.line == nil or not in_list() then return nil end
			local stop_index0 = walk.next_stop()
			if stop_index0 == nil then return nil end
			---@type react.TreeNodeId[]
			local children = { spacer }
			local problem_ok, problem = pcall(stop_problem_text, walk.line, stop_index0)
			if problem_ok and problem then
				-- mouse-transparent, so it never takes the button's clicks; the button's tooltip says why
				children[#children + 1] = builtin.ImageView{
					meta = { class = "uio-station-stop-alert", mouseTransparent = true },
					path = "::/gui/statistics/icons/alert.tga",
					scaling = builtin.type.ImageViewScaling.AutoFit,
				}
			end
			children[#children + 1] = button{
				line = walk.line,
				stopIndex0 = stop_index0,
				id = station_terminals.button_id(walk.line, stop_index0),
				problem = problem_ok and problem or nil,
			}
			return builtin.Component{
				meta = { class = "horizontal-spacer, uio-station-terminal"
					.. (problem_ok and problem and ", uio-station-terminal-alert" or "") },
				layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children },
			}
		end)
		if not ok then report("row", result) end
		return ok and result or spacer
	end
end

--- Called by installer.lua before the UI starts.
---@param _replacement_api react.ReplacementApi
function station_terminals.install(_replacement_api)
	if type(orderedPairs) ~= "function" then error("orderedPairs not found") end
	if gui_react_util.makeHorizontalSpacer == nil then error("gui_react_util.makeHorizontalSpacer not found") end
	if react.getCurrentRecipeName == nil or type(_react) ~= "table" then error("react internals not found") end
	local function in_list()
		return station_terminals.in_base_list(current_recipe, station_window_replaced)
	end
	-- generic: helpers the whole UI uses, changed here only while the station window's stop list renders
	priority.chain(_G, "orderedPairs", function(previous)
		return station_terminals.wrap_ordered_pairs(previous, in_list)
	end, true)
	priority.chain(gui_react_util, "makeHorizontalSpacer", function(previous)
		return station_terminals.wrap_spacer(previous, in_list, terminals.TerminalButton)
	end, true)
	debugPrint("[ui_overhaul] station terminal buttons installed")
end

return station_terminals
