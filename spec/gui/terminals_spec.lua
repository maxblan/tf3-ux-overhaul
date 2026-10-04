-- terminals.lua needs base GUI modules; stand-ins record what the module registers and calls.

-- What the spec's stand-in for `api` provides: only what line_state and common_params read.
---@class spec.terminals.Api
---@field engine { entityExists: fun(e: Engine.Entity): boolean }
---@field type { StationTerminal: { new: fun(station: integer, terminal: integer): StationTerminal } }

-- What the label spec's stand-in for `api` provides: the cargo class repository.
---@class spec.terminals.LabelApi
---@field res { cargoClassRep: spec.terminals.CargoClassRep }

---@class spec.terminals.CargoClassRep
---@field getCargoClassId fun(cargoClass: string): integer
---@field get fun(id: integer): CargoClass
---@type table<function, string>
local registered = {}
---@param p any the popover params, whatever the caller passed
---@return { popover: any }
local base_popover = function(p) return { popover = p } end
local popover_react_util = { PopoverWindowContent = base_popover }
package.loaded["::/gui/main/builtin.lua"] = { BoxLayout = function(t) return t end }
package.loaded["::/gui/main/engine_react_util.tl"] = {}
package.loaded["::/scripts/table_util.tl"] = {
	-- a deep copy of any value (hence any)
	---@param obj any
	---@return any
	copy = function(obj)
		---@param o any
		---@return any
		local function copy(o)
			if type(o) ~= "table" then return o end
			---@type table<any, any>
			local r = {}
			for k, v in pairs(o --[[@as table<any, any>]]) do r[k] = copy(v) end
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
	---@param name string
	---@param fn function
	---@return function
	RegisterRecipe = function(name, fn)
		local recipe = function(...) return fn(...) end
		registered[recipe] = name
		return recipe
	end,
	---@param recipe function
	---@return string
	GetRecipeName = function(recipe) return registered[recipe] end,
}
_G.debugPrint = _G.debugPrint or function() end

local terminals = require("/ui_overhaul/gui/terminals.lua")
local react = package.loaded["::/gui/main/react.lua"]

local base_terminals = react.RegisterRecipe("TerminalSelection", function() end)
local cargo_filter = react.RegisterRecipe("CargoFilterContent", function() end)

-- Only the fields usage() and apply() read; the rest of a TerminalData is not needed here.
---@param fields table
---@return uo.gui.terminals.TerminalData
local function terminal_data(fields) return fields --[[@as uo.gui.terminals.TerminalData]] end

---@return (string|integer|boolean)[][] log
---@return uo.gui.terminals.CommonParams
local function calls()
	---@type (string|integer|boolean)[][]
	local log = {}
	return log, {
		iconPaths = { problemAlert = "", problemArrow = "" },
		changeMainTerminal = function(...) log[#log + 1] = { "main", ... } end,
		selectAlternativeTerminal = function(...) log[#log + 1] = { "alternative", ... } end,
	}
end

describe("terminals", function()
	it("hands the terminal popover our recipe and keeps everything else", function()
		local params = { lineEntity = 1, stopIndex = 0, viaState = {}, commonParams = {} }
		local p = { meta = { forceFocusable = true }, recipe = base_terminals, params = params, onClose = print }
		local swapped = terminals.swap(p, react.GetRecipeName)
		---@cast swapped game.gui.main.popover_react_util.PopoverWindowParam -- the copy of p
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
		---@diagnostic disable-next-line: param-type-mismatch -- an odd argument, on purpose
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
		assert.are.equal("Main", terminals.usage(terminal_data{ current = true, alternativeHere = true }))
		assert.are.equal("Alternative", terminals.usage(terminal_data{ alternativeHere = true }))
		assert.are.equal("Unused", terminals.usage(terminal_data{}))
	end)

	it("makes exactly one line change per click", function()
		local terminal = terminal_data{ stationIndex1 = 2, terminalIndex1 = 3 }
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
		assert.is_false(terminals.apply(common, 1, terminal_data{}, "Main", "Unused"))
		assert.is_false(terminals.apply(common, 1, terminal_data{}, "Alternative", "Alternative"))
		assert.is_false(terminals.apply(common, 1, terminal_data{}, "Unused", nil))
		assert.are.same({}, log)
	end)

	it("counts stop numbers like the Line Manager, waypoints included", function()
		local path = { { stop = {} }, { waypoint = {} }, { stop = {} }, { stop = {} } }
		assert.are.equal(1, terminals.stop_number(path, 0))
		assert.are.equal(3, terminals.stop_number(path, 1))
		assert.are.equal(4, terminals.stop_number(path, 2))
		assert.is_nil(terminals.stop_number(path, 3))
	end)

	describe("terminal label", function()
		---@type api, fun(text: string): string
		local saved_api, saved_tr
		before_each(function()
			saved_api, saved_tr = _G.api, _G._
			---@type spec.terminals.LabelApi
			local mock = { res = { cargoClassRep = {
				getCargoClassId = function(name)
					-- the engine takes a string only
					if type(name) ~= "string" then error("getCargoClassId: string expected") end
					return name == "COAL" and 3 or -1
				end,
				get = function(_id) return { name = "Coal", color = { x = 0.1, y = 0.2, z = 0.3 } } end,
			} } }
			-- A partial stand-in (spec.terminals.LabelApi). The cast keeps LuaLS from merging the mock's
			-- types into the global `api` everywhere else; a plain assignment would.
			_G.api = mock --[[@as api]]
			---@param text string
			---@return string
			local function tr(text) return text end
			_G._ = tr
		end)
		after_each(function() _G.api, _G._ = saved_api, saved_tr end)

		it("names the cargo class of a specialised terminal, with its colour", function()
			local text, color = terminals.terminal_label(terminal_data{ isCargoTerminal = true,
				terminalSpecialization = "COAL" })
			assert.are.equal("Coal", text)
			assert.are.same({ x = 0.1, y = 0.2, z = 0.3 }, color)
		end)

		it("takes a cargo terminal without a cargo class for one that takes all cargo", function()
			assert.are.equal("All Cargo Types", (terminals.terminal_label(terminal_data{ isCargoTerminal = true })))
			assert.are.equal("All Cargo Types", (terminals.terminal_label(terminal_data{ isCargoTerminal = true,
				terminalSpecialization = "UNIVERSAL" })))
		end)

		it("labels passenger terminals as the base does", function()
			assert.are.equal("Passenger", (terminals.terminal_label(terminal_data{ isPassengerTerminal = true })))
			assert.are.equal("Passenger and Cargo", (terminals.terminal_label(terminal_data{
				isPassengerTerminal = true, isCargoTerminal = true })))
		end)
	end)

	describe("outside the Line Manager", function()
		---@type api
		local saved_api
		---@type integer, integer
		local revision, reads
		before_each(function()
			saved_api = _G.api
			---@type spec.terminals.Api
			local mock = {
				engine = { entityExists = function(e) return e == 7 end },
				type = { StationTerminal = { new = function(station, terminal)
					return { station = station, terminal = terminal }
				end } },
			}
			-- A partial stand-in (spec.terminals.Api). The cast keeps LuaLS from merging the mock's types into
			-- the global `api` everywhere else; a plain assignment would.
			_G.api = mock --[[@as api]]
			revision, reads = 1, 0
		end)
		after_each(function() _G.api = saved_api end)

		---@return uo.gui.terminals.LineState
		local function line_state()
			return terminals.line_state(7, function()
				reads = reads + 1
				local line = { path = { { stop = { station1 = 1, terminal1 = 1, alternativeTerminals = {
					{ station = 0, terminal = 2 },
				} } } } }
				-- only the path is read here, so the rest of a ReactLine is left out
				return line --[[@as game.gui.line_vehicle_mgmt.line.ReactLine]]
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
			---@type game.gui.line_vehicle_mgmt.line.ReactLine[]
			local sent = {}
			local state = line_state()
			local common = terminals.common_params(state, function(l) sent[#sent + 1] = l end)
			local before = state.old()
			---@cast before -nil -- line 7 exists in the stand-in
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
			---@type game.gui.line_vehicle_mgmt.line.ReactLine[]
			local sent = {}
			local common = terminals.common_params(line_state(), function(l) sent[#sent + 1] = l end)
			local line_state_view = common.lineState
			---@cast line_state_view -nil -- common_params always sets it
			local edited = line_state_view:old()
			---@cast edited -nil -- line 7 exists in the stand-in
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
	-- the state holds whatever the hook's function returns (hence any)
	---@param name string
	---@return fun(fn: fun(old: nil): any): { old: fun(): any }
	local function step_state(name)
		return function(fn)
			local value = fn(nil)
			fake.hook(name)
			return { old = function() return value end }
		end
	end
	---@type uo.gui.terminals
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

	it("declares its hooks without a via state too, and reads and logs nothing then", function()
		local saved_print, read_problems = _G.debugPrint, module.read_problems
		local logged, scans = 0, 0
		local function count() logged = logged + 1 end
		_G.debugPrint = count
		module.read_problems = function() scans = scans + 1 return {} end
		local child = fake.mount(fake.recipe("TerminalSelection", 1))
		local node = child.render({ commonParams = {}, lineEntity = 1 })
		_G.debugPrint, module.read_problems = saved_print, read_problems
		assert.are.same({ "useStepState", "useStepStateTimer", "useStepStateTimer" }, child.hooks)
		assert.are.same({ layout = {} }, node)
		assert.are.same({ 0, 0 }, { logged, scans })
		assert.is_false(module.switch.failed)
	end)

	it("switches to the base popover once after a failure, never back", function()
		local params = { viaState = { old = function() return {} end }, commonParams = {}, lineEntity = 1 }
		-- the base popover the Line Manager opened, taken over
		local swapped = module.swap({ recipe = base, params = params }, fake.react.GetRecipeName)
		---@cast swapped game.gui.main.popover_react_util.PopoverWindowParam -- the copy of the base popover's
		assert.are.equal(module.TerminalSelection, swapped.recipe)

		local parent = fake.mount(module.TerminalSelection)
		---@type spec.FakeNode the fallback parent's child: the mod's recipe
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
