-- station_terminals.lua needs base GUI modules; stand-ins record what the wrappers return.
package.loaded["::/gui/main/builtin.lua"] = {
	Component = function(t) return { component = t } end,
	BoxLayout = function(t) return t end,
	type = { Orientation = { Horizontal = "h" } },
}
package.loaded["::/gui/main/gui_react_util.tl"] = {}
package.loaded["::/gui/main/react.lua"] = {}
package.loaded["::/gui/entity_window/station_group/station_group.tl"] = function() end
package.loaded["ui_overhaul_1::/ui_overhaul/gui/terminals.lua"] = {}
_G.debugPrint = _G.debugPrint or function() end

local station_terminals = require("/ui_overhaul/gui/station_terminals.lua")

local function sorted_pairs(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	local i = 0
	return function()
		i = i + 1
		return keys[i], t[keys[i]]
	end, t, nil
end

local function button(p) return { button = p } end
local function spacer() return "spacer" end

-- Renders a list the way TerminalStops does: one spacer per line with one stop, else one per stop.
local function render_list(ordered_pairs, make_spacer, list)
	local rows = {}
	for _line, stops in ordered_pairs(list) do
		if #stops == 1 then
			rows[#rows + 1] = make_spacer()
		else
			for _i = 1, #stops do rows[#rows + 1] = make_spacer() end
		end
	end
	return rows
end

local function stops(...)
	local result = {}
	for i, index in ipairs({ ... }) do result[i] = { stopIndex0 = index } end
	return result
end

describe("station terminals", function()
	it("puts the button of each row's stop next to its spacer", function()
		local active = function() return true end
		local pairs_ = station_terminals.wrap_ordered_pairs(sorted_pairs, active)
		local spacer_ = station_terminals.wrap_spacer(spacer, active, button)
		local rows = render_list(pairs_, spacer_, { [10] = stops(3), [20] = stops(0, 4) })
		local found = {}
		for i, row in ipairs(rows) do
			local children = row.component.layout.children
			assert.are.equal("spacer", children[1])
			found[i] = { children[2].button.line, children[2].button.stopIndex0 }
		end
		assert.are.same({ { 10, 3 }, { 20, 0 }, { 20, 4 } }, found)
		-- after the list, a spacer elsewhere is a plain spacer again
		assert.are.equal("spacer", spacer_())
	end)

	it("changes nothing outside the list or when the station window is replaced", function()
		local inactive = function() return false end
		local pairs_ = station_terminals.wrap_ordered_pairs(sorted_pairs, inactive)
		local spacer_ = station_terminals.wrap_spacer(spacer, inactive, button)
		assert.are.same({ "spacer", "spacer" }, render_list(pairs_, spacer_, { [1] = stops(0), [2] = stops(1) }))
		assert.is_false(station_terminals.in_base_list(function() return "TerminalStops" end,
			function() return true end))
		assert.is_false(station_terminals.in_base_list(function() return "LineStopButton" end,
			function() return false end))
		assert.is_false(station_terminals.in_base_list(function() error("no recipe") end, function() return false end))
		assert.is_true(station_terminals.in_base_list(function() return "TerminalStops" end,
			function() return false end))
	end)

	it("keeps the plain spacer if the button fails", function()
		local active = function() return true end
		local pairs_ = station_terminals.wrap_ordered_pairs(sorted_pairs, active)
		local spacer_ = station_terminals.wrap_spacer(spacer, active, function() error("boom") end)
		assert.are.same({ "spacer" }, render_list(pairs_, spacer_, { [1] = stops(0) }))
	end)

	it("iterates like the wrapped function", function()
		local pairs_ = station_terminals.wrap_ordered_pairs(sorted_pairs, function() return true end)
		local keys = {}
		for k, v in pairs_({ b = 2, a = 1 }) do keys[#keys + 1] = k .. v end
		assert.are.same({ "a1", "b2" }, keys)
	end)
end)
