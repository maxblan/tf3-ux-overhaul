-- terminals.lua needs base GUI modules; stand-ins record what the module registers and calls.
local registered = {}
local base_popover = function(p) return { popover = p } end
local popover_react_util = { PopoverWindowContent = base_popover }
package.loaded["::/gui/main/builtin.lua"] = { BoxLayout = function(t) return t end }
package.loaded["::/gui/main/engine_react_util.tl"] = {}
package.loaded["::/scripts/table_util.tl"] = {
	copy = function(obj)
		local function copy(o)
			if type(o) ~= "table" then return o end
			local r = {}
			for k, v in pairs(o) do r[k] = copy(v) end
			return r
		end
		return copy(obj)
	end,
}
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
		local params = { lineEntity = 1, stopIndex = 0, viaState = {}, commonParams = {} }
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

	it("leaves popovers of the base name with other parameters to their mod", function()
		-- Terminal Selector: a recipe of its own named TerminalSelection, opened from the station window
		local station_popover = { recipe = base_terminals, params = { lineEntity = 1, stopIndex0 = 2 } }
		assert.are.equal(station_popover, terminals.swap(station_popover, react.GetRecipeName))
		local no_params = { recipe = base_terminals }
		assert.are.equal(no_params, terminals.swap(no_params, react.GetRecipeName))
	end)

	it("installs a wrapper that chains to the previous PopoverWindowContent", function()
		terminals.install({})
		assert.is_true(base_popover ~= popover_react_util.PopoverWindowContent)
		local result = popover_react_util.PopoverWindowContent{
			recipe = base_terminals, params = { viaState = {}, commonParams = {} },
		}
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

	it("counts stop numbers like the Line Manager, waypoints included", function()
		local path = { { stop = {} }, { waypoint = {} }, { stop = {} }, { stop = {} } }
		assert.are.equal(1, terminals.stop_number(path, 0))
		assert.are.equal(3, terminals.stop_number(path, 1))
		assert.are.equal(4, terminals.stop_number(path, 2))
		assert.is_nil(terminals.stop_number(path, 3))
	end)

	describe("outside the Line Manager", function()
		local saved_api
		local revision, reads
		before_each(function()
			saved_api = _G.api
			_G.api = {
				engine = { entityExists = function(e) return e == 7 end },
				type = { StationTerminal = { new = function(station, terminal)
					return { station = station, terminal = terminal }
				end } },
			}
			revision, reads = 1, 0
		end)
		after_each(function() _G.api = saved_api end)

		local function line_state()
			return terminals.line_state(7, function()
				reads = reads + 1
				return { path = { { stop = { station1 = 1, terminal1 = 1, alternativeTerminals = {
					{ station = 0, terminal = 2 },
				} } } } }
			end, function() return { num = { revision, 0, 0 } } end)
		end

		it("keeps the same line table until the line changes", function()
			local state = line_state()
			local first = state.old()
			assert.are.equal(first, state.old())
			assert.are.equal(1, reads)
			revision = 2
			assert.is_true(first ~= state.old())
			assert.are.equal(2, reads)
			assert.is_nil(terminals.line_state(8, error, error).old()) -- removed line
		end)

		it("sends one changed copy per terminal change", function()
			local sent = {}
			local state = line_state()
			local common = terminals.common_params(state, function(l) sent[#sent + 1] = l end)
			local before = state.old()
			common.changeMainTerminal(1, 1, 3)
			common.selectAlternativeTerminal(1, 1, 2, true)
			common.selectAlternativeTerminal(1, 1, 3, false)
			assert.are.equal(3, #sent)
			assert.are.equal(3, sent[1].path[1].stop.terminal1)
			assert.are.same({ { station = 0, terminal = 2 }, { station = 0, terminal = 1 } },
				sent[2].path[1].stop.alternativeTerminals)
			assert.are.same({}, sent[3].path[1].stop.alternativeTerminals)
			assert.are.equal(1, before.path[1].stop.terminal1) -- the read line is not changed
		end)

		it("sends a change made on lineState:old() before changeMainTerminal (Easy Terminal Assignment)", function()
			local sent = {}
			local common = terminals.common_params(line_state(), function(l) sent[#sent + 1] = l end)
			local edited = common.lineState:old()
			edited.path[1].stop.alternativeTerminals = {}
			common.changeMainTerminal(1, 1, 2)
			assert.are.equal(1, #sent)
			assert.are.same({}, sent[1].path[1].stop.alternativeTerminals)
			assert.are.equal(2, sent[1].path[1].stop.terminal1)
		end)
	end)
end)

describe("terminals popover fallback", function()
	local fake_react = require("fake_react")
	local fake = fake_react.new()
	local builtin = fake_react.any()
	builtin.BoxLayout = function(t) return { layout = t } end
	local function step_state(name)
		return function(fn)
			local value = fn(nil)
			fake.hook(name)
			return { old = function() return value end }
		end
	end
	local module = fake_react.load("/ui_overhaul/gui/terminals.lua", {
		["::/gui/main/react.lua"] = fake.react,
		["::/gui/main/builtin.lua"] = builtin,
		["::/gui/main/engine_react_util.tl"] = {
			useStepState = step_state("useStepState"),
			useStepStateTimer = step_state("useStepStateTimer"),
		},
	})
	local base = fake.react.RegisterRecipe("TerminalSelection", function() end)
	local PARENT_HOOKS = { "useState", "onStep", "useRef", "useRef" }

	it("declares its hooks without a via state too, and shows nothing then", function()
		local child = fake.mount(fake.recipe("TerminalSelection", 1))
		local node = child.render({ commonParams = {} })
		assert.are.same({ "useStepState", "useStepStateTimer", "useStepStateTimer" }, child.hooks)
		assert.are.same({ layout = {} }, node)
		assert.is_false(module.switch.failed)
	end)

	it("switches to the base popover once after a failure, never back", function()
		local params = { viaState = { old = function() return {} end }, commonParams = {}, lineEntity = 1 }
		-- the base popover the Line Manager opened, taken over
		local swapped = module.swap({ recipe = base, params = params }, fake.react.GetRecipeName)
		assert.are.equal(module.TerminalSelection, swapped.recipe)

		local parent = fake.mount(module.TerminalSelection)
		local child_node = parent.render(params).layout.children[1]
		assert.are.same(PARENT_HOOKS, parent.hooks)
		local child = fake.render_node(child_node) -- no engine here: fails after its hooks
		assert.is_true(module.switch.failed)
		local hooks = child.hooks
		assert.are.same({ "useStepState", "useStepStateTimer", "useStepStateTimer" }, hooks)
		child.render(params)
		assert.are.same(hooks, child.hooks)

		parent.step()
		local node = parent.render(params)
		assert.are.same(PARENT_HOOKS, parent.hooks)
		assert.are.equal(base, node.layout.children[1].recipe)
		assert.are.equal(base, parent.render(params).layout.children[1].recipe)
	end)
end)
