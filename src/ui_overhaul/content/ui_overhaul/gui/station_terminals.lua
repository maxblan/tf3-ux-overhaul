--- Station window, Terminals list: a "Select Terminals" button on every line stop, at the right of
-- the row before the waiting count. It opens the Line Manager's terminal popover for that stop
-- (terminals.TerminalButton), so the terminals of a line can be set from the station. A line whose
-- vehicles cannot reach this stop (no path into it, an incompatible or doubled stop) gets the
-- statistics alert icon in front of the button, with the game's problem text as its tooltip.
--
-- The list (TerminalStops, gui/entity_window/station_group/station_group.tl) is file-local and cannot
-- be replaced; replacing the whole station window would clash with every other mod that does. Two
-- calls the list makes are wrapped instead, both looked up when they run:
--   * orderedPairs (global), which walks the list's lines: it records the line of each row;
--   * gui_react_util.makeHorizontalSpacer, called once in each row before the waiting count (once per
--     line with one stop here, once per stop otherwise): the spacer is returned with the button in it.
-- Both act only while the recipe TerminalStops renders, and only while the station window is the base
-- one: a mod that replaces it (Terminal Selector) brings its own buttons. On any error the row stays
-- as it is and one line is logged. Installed by station_terminals.script.lua.
-- @module ui_overhaul.gui.station_terminals
local builtin = require("::/gui/main/builtin.lua")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local react = require("::/gui/main/react.lua")
local station_group = require("::/gui/entity_window/station_group/station_group.tl")
local terminals = require("ui_overhaul_1::/ui_overhaul/gui/terminals.lua")
local line_problems = require("/ui_overhaul/core/line_problems.lua")

local station_terminals = {}

local LIST_RECIPE = "TerminalStops"

local reported = {}
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] station terminal buttons: ", key, ": ", tostring(err))
end

--- True while the base list renders: the current recipe is `LIST_RECIPE` and no mod replaced the
-- station window. `current_recipe` and `replaced` are parameters for the specs.
function station_terminals.in_base_list(current_recipe, replaced)
	local ok, name = pcall(current_recipe)
	return ok and name == LIST_RECIPE and not replaced()
end

local function current_recipe()
	return react.getCurrentRecipeName()
end

local function station_window_replaced()
	local id = react.GetRecipeId(station_group)
	return id ~= nil and _react.recipeReplace[id] ~= nil
end

--- Walk state of one list render: the line of the current row and how many rows of it were made.
--- `row(stops)` returns the stop (0-based) of the next spacer of the line with `stops` here.
function station_terminals.new_walk()
	local walk = {}
	function walk.enter(line, stops)
		walk.line, walk.stops, walk.rows = line, stops, 0
	end
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
function station_terminals.button_id(line, stop_index0)
	return "uio.terminals.station." .. tostring(line) .. "." .. tostring(stop_index0)
end

--- orderedPairs that records each line it yields while the list renders.
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
local problems_cache = {}
local PROBLEMS_SECONDS = 2

local PRUNE_SECONDS = 60 -- lines not looked at for this long are dropped from the cache

local function stop_problem_text(line, stop_index0)
	local now = os.clock()
	local entry = problems_cache[line]
	if not entry or now - entry.time > PROBLEMS_SECONDS then
		for key, old in pairs(problems_cache) do
			if now - old.time > PRUNE_SECONDS then problems_cache[key] = nil end
		end
		local ok, data = pcall(terminals.read_problems, line)
		entry = { time = now, data = ok and data or nil }
		problems_cache[line] = entry
	end
	if not entry.data then return nil end
	local texts = {}
	for _i, problem in ipairs(line_problems.stop_problems(entry.data.stops, entry.data.segments, stop_index0 + 1)) do
		texts[#texts + 1] = terminals.problem_text(problem)
	end
	return #texts > 0 and table.concat(texts, "\n") or nil
end

--- The spacer, with the button of the current row's stop at its right while the list renders.
function station_terminals.wrap_spacer(previous, in_list, button)
	return function(...)
		local spacer = previous(...)
		local ok, result = pcall(function()
			if walk.line == nil or not in_list() then return nil end
			local stop_index0 = walk.next_stop()
			if stop_index0 == nil then return nil end
			local children = { spacer }
			local problem_ok, problem = pcall(stop_problem_text, walk.line, stop_index0)
			if problem_ok and problem then
				children[#children + 1] = builtin.ImageView{
					meta = { class = "uio-station-stop-alert", tooltip = problem },
					path = "::/gui/statistics/icons/alert.tga",
					scaling = builtin.type.ImageViewScaling.AutoFit,
				}
			end
			children[#children + 1] = button{
				line = walk.line,
				stopIndex0 = stop_index0,
				id = station_terminals.button_id(walk.line, stop_index0),
			}
			return builtin.Component{
				meta = { class = "horizontal-spacer, uio-station-terminal" },
				layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children },
			}
		end)
		if not ok then report("row", result) end
		return ok and result or spacer
	end
end

--- Called from the react-replacement-config before the UI starts.
function station_terminals.install(_replacement_api)
	if type(orderedPairs) ~= "function" then error("orderedPairs not found") end
	if gui_react_util.makeHorizontalSpacer == nil then error("gui_react_util.makeHorizontalSpacer not found") end
	if react.getCurrentRecipeName == nil or type(_react) ~= "table" then error("react internals not found") end
	local function in_list()
		return station_terminals.in_base_list(current_recipe, station_window_replaced)
	end
	orderedPairs = station_terminals.wrap_ordered_pairs(orderedPairs, in_list)
	gui_react_util.makeHorizontalSpacer = station_terminals.wrap_spacer(
		gui_react_util.makeHorizontalSpacer, in_list, terminals.TerminalButton)
	debugPrint("[ui_overhaul] station terminal buttons installed")
end

return station_terminals
