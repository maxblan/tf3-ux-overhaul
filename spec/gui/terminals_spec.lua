-- terminals.lua needs base GUI modules; stand-ins record what the module registers and calls.
local registered = {}
local base_popover = function(p) return { popover = p } end
local popover_react_util = { PopoverWindowContent = base_popover }
package.loaded["::/gui/main/builtin.lua"] = { BoxLayout = function(t) return t end }
package.loaded["::/gui/main/engine_react_util.tl"] = {}
package.loaded["::/gui/main/gui_react_util.tl"] = {}
package.loaded["::/scripts/lang_util.tl"] = {}
package.loaded["::/gui/line_vehicle_mgmt/line_react_util.tl"] = {}
package.loaded["::/gui/line_vehicle_mgmt/line_util.tl"] = {}
package.loaded["::/gui/main/popover_react_util.tl"] = popover_react_util
package.loaded["::/gui/main/styleutil.tl"] = {}
package.loaded["::/gui/main/react.lua"] = {
	RegisterRecipe = function(name, fn)
		local recipe = function(...) return fn(...) end
		registered[recipe] = name
		return recipe
	end,
	GetRecipeName = function(recipe) return registered[recipe] end,
}
_G.debugPrint = _G.debugPrint or function() end

local terminals = require("/ui_overhaul/gui/terminals.lua")
local react = package.loaded["::/gui/main/react.lua"]

local base_terminals = react.RegisterRecipe("TerminalSelection", function() end)
local cargo_filter = react.RegisterRecipe("CargoFilterContent", function() end)

local function calls()
	local log = {}
	return log, {
		changeMainTerminal = function(...) log[#log + 1] = { "main", ... } end,
		selectAlternativeTerminal = function(...) log[#log + 1] = { "alternative", ... } end,
	}
end

describe("terminals", function()
	it("hands the terminal popover our recipe and keeps everything else", function()
		local params = { lineEntity = 1, stopIndex = 0, viaState = {} }
		local p = { meta = { forceFocusable = true }, recipe = base_terminals, params = params, onClose = print }
		local swapped = terminals.swap(p, react.GetRecipeName)
		assert.are.equal(terminals.TerminalSelection, swapped.recipe)
		assert.are.equal(params, swapped.params)
		assert.are.equal(p.meta, swapped.meta)
		assert.are.equal(print, swapped.onClose)
		assert.are.equal(base_terminals, p.recipe) -- the caller's table is not changed
		assert.are.equal("TerminalSelection", react.GetRecipeName(swapped.recipe)) -- base stylesheet applies
	end)

	it("passes other popovers and odd arguments through unchanged", function()
		local p = { recipe = cargo_filter, params = {} }
		assert.are.equal(p, terminals.swap(p, react.GetRecipeName))
		local plain = { recipe = function() end }
		assert.are.equal(plain, terminals.swap(plain, react.GetRecipeName))
		assert.are.equal("ref", terminals.swap("ref", react.GetRecipeName))
		local ours = { recipe = terminals.TerminalSelection }
		assert.are.equal(ours, terminals.swap(ours, react.GetRecipeName))
	end)

	it("installs a wrapper that chains to the previous PopoverWindowContent", function()
		terminals.install({})
		assert.is_true(base_popover ~= popover_react_util.PopoverWindowContent)
		local result = popover_react_util.PopoverWindowContent{ recipe = base_terminals, params = {} }
		assert.are.equal(terminals.TerminalSelection, result.popover.recipe)
		local other = { recipe = cargo_filter }
		assert.are.equal(other, popover_react_util.PopoverWindowContent(other).popover)
	end)

	it("reads the usage like the base drop-down list", function()
		assert.are.equal("Main", terminals.usage{ current = true, alternativeHere = true })
		assert.are.equal("Alternative", terminals.usage{ alternativeHere = true })
		assert.are.equal("Unused", terminals.usage{})
	end)

	it("makes exactly one line change per click", function()
		local terminal = { stationIndex1 = 2, terminalIndex1 = 3 }
		local log, common = calls()
		assert.is_true(terminals.apply(common, 4, terminal, "Unused", "Main"))
		assert.is_true(terminals.apply(common, 4, terminal, "Unused", "Alternative"))
		assert.is_true(terminals.apply(common, 4, terminal, "Alternative", "Unused"))
		assert.are.same({
			{ "main", 4, 2, 3 },
			{ "alternative", 4, 2, 3, true },
			{ "alternative", 4, 2, 3, false },
		}, log)
	end)

	it("changes nothing for the preferred terminal or an unchanged usage", function()
		local log, common = calls()
		assert.is_false(terminals.apply(common, 1, {}, "Main", "Unused"))
		assert.is_false(terminals.apply(common, 1, {}, "Alternative", "Alternative"))
		assert.is_false(terminals.apply(common, 1, {}, "Unused", nil))
		assert.are.same({}, log)
	end)
end)
