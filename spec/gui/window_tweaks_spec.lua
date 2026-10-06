-- window_tweaks.lua: remembered entity-window sections chain on the base function and still collapse
-- for Modify; the town level text lives in a child recipe that the base card drops after a failure. The
-- base modules are stand-ins (restored after loading, so other specs keep theirs).
_G.debugPrint = _G.debugPrint or function() end
local registered = {} ---@type table<string, function> recipe name -> its body
local wrappers = {} ---@type table<string, function> wrapper recipe name -> the recipe it wraps
local original_fails = false -- the stand-in CallOriginalRecipe raises, as for a field that is no recipe

-- The stand-in for a window's useState({}): set() takes effect on the next render (new_window).
---@class spec.window_tweaks.State
---@field value table<string, boolean>
---@field pending table<string, boolean>?
local State = {}

---@return table<string, boolean>
function State:old() return self.value end

---@param v table<string, boolean>
function State:set(v) self.pending = v end

-- Lua copy of the base function (content_card.tl:457-477)
---@param state spec.window_tweaks.State
---@param only_one_expandable boolean
---@return fun(key: string, expanded: boolean) update
---@return fun(key: string): boolean is_expanded
local function base_collapsible(state, only_one_expandable)
	---@param key string
	---@param expanded boolean
	local function update(key, expanded)
		local prev = {} ---@type table<string, boolean>
		for k, v in pairs(state:old()) do prev[k] = v end
		if only_one_expandable then
			for k in pairs(prev) do prev[k] = false end
		end
		prev[key] = expanded
		state:set(prev)
	end
	---@param key string
	---@return boolean
	local function is_expanded(key) return state:old()[key] == true end
	return update, is_expanded
end

local content_card = {
	makeContentCardsCollapsibleFunctions = base_collapsible,
	---@param recipe function
	---@param param any
	---@return { recipe: function, param: any }
	makeRecipeAndParam = function(recipe, param) return { recipe = recipe, param = param } end,
}
-- the hooks the town level text uses, set by each spec
---@class spec.window_tweaks.EngineReactUtil
---@field useStepStateParallelSimple fun(fn: string): { old: fun(): any }
---@field useStepState fun(fn: fun(): any): { old: fun(): any }
local engine_react_util = {}
local town_util = {
	GetRatings = function()
		return { { name = "Traffic", getRatingFnName = "traffic" }, { name = "Noise", getRatingFnName = "noise" } }
	end,
	---@param level integer
	---@return string
	level2name = function(level) return "Level " .. level end,
}

---@type table<string, table>
local stand_ins = {
	["::/gui/main/react.lua"] = {
		-- as in the game, calling a recipe makes a node; its body runs later, in its own instance
		---@param name string
		---@param fn function
		---@return fun(p: any): { recipe: string, params: any }
		RegisterRecipe = function(name, fn)
			registered[name] = fn
			return function(p) return { recipe = name, params = p } end
		end,
		---@param name string
		---@param wrapped function
		---@param fn function
		---@return fun(p: any): { recipe: string, params: any }
		RegisterWrapperRecipe = function(name, wrapped, fn)
			registered[name], wrappers[name] = fn, wrapped
			return function(p) return { recipe = name, params = p } end
		end,
		---@param recipe function
		---@param p any
		---@return { original: function, params: any }
		CallOriginalRecipe = function(recipe, p)
			if original_fails then error("not a recipe") end
			return { original = recipe, params = p }
		end,
		---@param _recipe function
		---@return integer
		GetRecipeId = function(_recipe) return 7 end,
	},
	["::/gui/main/builtin.lua"] = {
		BoxLayout = function(t) return { box = t } end,
		---@param t builtin.TextViewParam
		---@return { text: string? }
		TextView = function(t) return { text = t.text } end,
		type = { Orientation = { Vertical = "vertical" } },
	},
	["::/gui/main/content_card.tl"] = content_card,
	["::/gui/entity_window/entity_window_util.tl"] = { ActionButtonBar = function() end },
	["::/game_mechanics/company/company_util.tl"] = { getConstructionDisableReason = function() end },
	["::/game_mechanics/company/company_metadata.tl"] = {},
	["::/game_mechanics/company/company_static_util.tl"] = {},
	["::/game_mechanics/company/company_progression_util.tl"] = {},
	["::/gui/main/engine_react_util.tl"] = engine_react_util,
	["::/scripts/lang_util.tl"] = {
		format = function(text, values) return (text:gsub("{(%w+)}", function(k) return tostring(values[k]) end)) end,
	},
	["::/game_mechanics/towns/town_util.tl"] = town_util,
	["::/game_mechanics/towns/town_cargo_util.tl"] = {
		getLevelAndFraction = function(experience) return math.floor(experience), experience % 1 end,
	},
}

local loaded = package.loaded ---@type table<string, any> module name -> module, of any type
local saved = {} ---@type table<string, any> module path -> what package.loaded held: any module
for path, module in pairs(stand_ins) do
	saved[path] = loaded[path]
	loaded[path] = module
end
local window_tweaks = require("/ui_overhaul/gui/window_tweaks.lua")
for path in pairs(stand_ins) do loaded[path] = saved[path] end

-- A window's useState({}): set() takes effect on the next render, as in the game.
---@return spec.window_tweaks.Window
local function new_window()
	local state = { value = {} } ---@type spec.window_tweaks.State
	setmetatable(state, { __index = State })
	---@class spec.window_tweaks.Window
	---@field update fun(key: string, expanded: boolean)
	---@field is_expanded fun(key: string): boolean
	local window = {}
	function window.render()
		if state.pending then state.value, state.pending = state.pending, nil end
		-- every base window passes onlyOneExpandable = true
		window.update, window.is_expanded = content_card.makeContentCardsCollapsibleFunctions(state, true)
	end
	window.render()
	return window
end

-- another mod's wrap, installed before UI Overhaul
local previous_patch_calls = {} ---@type boolean[]
local before = content_card.makeContentCardsCollapsibleFunctions
---@param state spec.window_tweaks.State
---@param only_one boolean
---@return fun(key: string, expanded: boolean) update
---@return fun(key: string): boolean is_expanded
content_card.makeContentCardsCollapsibleFunctions = function(state, only_one)
	previous_patch_calls[#previous_patch_calls + 1] = only_one
	return before(state, only_one)
end
local replaced = {} ---@type table<function, function> base recipe -> replacement
local replacement_api = { ReplaceRecipe = function(recipe, replacement) replaced[recipe] = replacement end }
window_tweaks.install_sections(replacement_api)
window_tweaks.install_sell(replacement_api)
window_tweaks.install_town(replacement_api)
window_tweaks.install_promotion(replacement_api)

describe("window_tweaks Sell confirmation", function()
	local util = stand_ins["::/gui/entity_window/entity_window_util.tl"]
	---@type fun(p: table): { original: function, params: any }
	local render = registered.UioActionButtonBar

	it("wraps the bar the field held, in the field, instead of replacing the recipe", function()
		assert.is_true(next(replaced) == nil)
		assert.is_true(wrappers.UioActionButtonBar ~= nil)
		assert.is_true(util.ActionButtonBar ~= wrappers.UioActionButtonBar)
	end)

	it("returns a node of exactly the wrapped recipe, with every other window's params unchanged", function()
		local params = { primaryButtons = { { tag = "entityWindow.warehouse.configure" } } }
		local node = render(params)
		assert.are.equal(wrappers.UioActionButtonBar, node.original)
		assert.are.equal(params, node.params)
	end)

	it("swaps the vehicle window's Sell for the confirming button", function()
		local sell = { tag = "entityWindow.vehicle.sell", sound = "Sell", description = "Sell", onClick = function() end }
		local params = { secondaryButtons = { sell } }
		local passed = render(params).params
		assert.is_true(params ~= passed)
		assert.are.equal("UioConfirmSellButton", passed.secondaryButtons[1].customItem.recipe)
		assert.is_nil(sell.customItem) -- the caller's button stays as it was
	end)

	it("passes odd params on unchanged instead of raising", function()
		local odd = { secondaryButtons = "not a list" }
		assert.are.equal(odd, render(odd).params)
	end)

	it("leaves the bar out instead of raising where the bar below cannot be made", function()
		original_fails = true
		local ok, node = pcall(render, { primaryButtons = {} })
		original_fails = false
		assert.is_true(ok)
		assert.are.same({}, node) -- a wrapper's empty child list (not nil: react.lua indexes it)
	end)

	it("steps aside where another mod replaced the bar below, which the wrap would hide", function()
		local globals = _G ---@type table<string, any>
		local saved_react = globals._react ---@type any the game's registry, or nil outside the game
		local wrapper = util.ActionButtonBar ---@type function
		globals._react = { recipeReplace = {} }
		assert.are.equal("kept", window_tweaks.settle_sell())
		assert.are.equal(wrapper, util.ActionButtonBar)
		globals._react = { recipeReplace = { [7] = function() end } }
		assert.are.equal("left out", window_tweaks.settle_sell())
		assert.are.equal(wrappers.UioActionButtonBar, util.ActionButtonBar)
		util.ActionButtonBar, globals._react = wrapper, saved_react
	end)
end)

describe("window_tweaks sections", function()
	it("chains on the previous function instead of replacing it", function()
		for k in pairs(previous_patch_calls) do previous_patch_calls[k] = nil end
		new_window()
		-- sections may open together; "collapse all" keeps the caller's onlyOneExpandable
		assert.are.same({ false, true }, previous_patch_calls)
	end)

	it("keeps several sections open and remembers them for the next window", function()
		local first = new_window()
		first.update("several.a", true)
		first.render()
		first.update("several.b", true)
		first.render()
		assert.is_true(first.is_expanded("several.a"))
		assert.is_true(first.is_expanded("several.b"))
		local second = new_window()
		assert.is_true(second.is_expanded("several.a"))
		assert.is_true(second.is_expanded("several.b"))
		second.update("several.a", false)
		second.render()
		assert.is_false(second.is_expanded("several.a"))
		assert.is_false(new_window().is_expanded("several.a"))
	end)

	it("collapse all before Modify also closes sections opened from the remembered state", function()
		local first = new_window()
		first.update("vehicleCarriage", true)
		first.render()
		first.update("vehicleCapacity", true)
		first.render()

		local second = new_window()
		second.update("vehicleCapacity", true) -- in this window's own state as well
		second.render()
		assert.is_true(second.is_expanded("vehicleCarriage")) -- only remembered
		second.update("", false) -- vehicle.tl:501, Modify
		second.render()
		assert.is_false(second.is_expanded("vehicleCarriage"))
		assert.is_false(second.is_expanded("vehicleCapacity"))
		-- stays collapsed in that window, as in the base game, until the player opens a section
		second.render()
		assert.is_false(second.is_expanded("vehicleCarriage"))
		second.update("vehicleCapacity", true)
		second.render()
		assert.is_true(second.is_expanded("vehicleCapacity"))
		assert.is_false(second.is_expanded("vehicleCarriage"))

		-- the collapse is not remembered: the next window opens the player's sections again
		assert.is_true(new_window().is_expanded("vehicleCarriage"))
	end)
end)

-- What the spec's stand-in for `api` provides: only what the town level text reads.
---@class spec.window_tweaks.Api
---@field engine { getComponent: fun(): { developmentActive: boolean } }
---@field type { ComponentType: { TOWN: integer } }
---@field util { toStringPercent: fun(f: number): string }

describe("window_tweaks town level", function()
	local globals = _G ---@type table<string, any> global name -> value, of any type
	local saved_globals = {} ---@type table<string, any> global name -> its value before the spec
	local logged ---@type string[]
	local hooks ---@type string[] hook calls in the current render
	local level_state ---@type { experience: number }?
	local throwing_hook ---@type string? parallel function name whose hook raises

	before_each(function()
		for _i, name in ipairs({ "api", "_", "debugPrint" }) do saved_globals[name] = globals[name] end
		---@param text string
		---@return string
		local function tr(text) return text end
		logged = {}
		---@param ... any
		local function record(...) logged[#logged + 1] = table.concat({ ... }) end
		_G._, _G.debugPrint = tr, record
		---@type spec.window_tweaks.Api
		local mock = {
			engine = { getComponent = function() return { developmentActive = true } end },
			type = { ComponentType = { TOWN = 1 } },
			util = { toStringPercent = function(f) return tostring(math.floor(f * 100 + 0.5)) .. "%" end },
		}
		-- A partial stand-in (spec.window_tweaks.Api). The cast keeps LuaLS from merging the mock's types
		-- into the global `api` everywhere else; a plain assignment would.
		_G.api = mock --[[@as api]]
		level_state = { experience = 2.5 }
		throwing_hook = nil
		---@param value any what the hook's state holds
		---@return { old: fun(): any }
		local function state(value) return { old = function() return value end } end
		engine_react_util.useStepStateParallelSimple = function(fn)
			hooks[#hooks + 1] = fn
			if fn == throwing_hook then error("parallel function failed") end
			if fn == "traffic" then return state("Poor") end
			if fn == "noise" then return state("Good") end
			if fn:find("getTownLevelWidgetState", 1, true) then return state(level_state) end
			return state("Excellent")
		end
		engine_react_util.useStepState = function(fn)
			hooks[#hooks + 1] = "useStepState"
			return state(fn())
		end
	end)

	after_each(function()
		for name, value in pairs(saved_globals) do globals[name] = value end
		window_tweaks.town_level_failed = false
	end)

	-- One mounted instance of a recipe: refs persist across its renders; `hooks` lists the hook calls
	-- of the last render.
	---@param name string
	---@return spec.window_tweaks.Instance
	local function mount(name)
		local refs, index = {}, 0 ---@type { value: any }[], integer
		local react = stand_ins["::/gui/main/react.lua"]
		---@class spec.window_tweaks.Instance
		local instance = {}
		---@param params table
		---@return any node what the recipe returned, any stand-in's node
		function instance.render(params)
			hooks, index = {}, 0
			---@param initial any
			---@return { get: fun(): any, set: fun(self: any, v: any) }
			react.useRef = function(initial)
				index = index + 1
				hooks[#hooks + 1] = "useRef"
				if refs[index] == nil then refs[index] = { value = initial } end
				local ref = refs[index]
				return { get = function() return ref.value end, set = function(_self, v) ref.value = v end }
			end
			local ok, node = pcall(registered[name], params)
			react.useRef = nil
			assert(ok, node)
			return node
		end
		return instance
	end

	---@param p any
	---@return { base: any }
	local inner = function(p) return { base = p } end
	local parent_params = { inner = inner, innerParam = { entityId = 7 } }

	---@param node any a stand-in BoxLayout node
	---@return string?
	local function text_of(node)
		local child = node.box.children[1] ---@type { text: string? }? the stand-in TextView's node
		return child and child.text
	end

	it("declares no hooks in the replacement and puts the text in a keyed child", function()
		local parent = mount("UioTownLevel")
		local node = parent.render(parent_params)
		assert.are.same({}, hooks)
		assert.are.same({ base = { entityId = 7 } }, node.box.children[1])
		local child = node.box.children[2] ---@type { recipe: string, params: table } the stand-in recipe node
		assert.are.equal("UioTownBottleneck", child.recipe)
		assert.are.equal("uio.town.bottleneck", child.params.meta.localKey)
		assert.are.equal(7, child.params.town)
	end)

	it("names the weakest factor and the progress to the next level", function()
		local node = mount("UioTownBottleneck").render({ town = 7 })
		assert.are.equal("Limited by Traffic  \xC2\xB7  50% Towards Level 3", text_of(node))
		assert.are.same({ "useRef", "traffic", "noise", "::/game_mechanics/towns/town_util_parallel.script@"
			.. "town_util_parallel.getRatingDeliveries", "::/game_mechanics/towns/town_util_parallel.script@"
			.. "town_util_parallel.getTownLevelWidgetState", "useStepState" }, hooks)
	end)

	it("leaves the progress out while the level state is still nil", function()
		level_state = nil
		local node = mount("UioTownBottleneck").render({ town = 7 })
		assert.are.equal("Limited by Traffic", text_of(node))
		assert.are.equal(0, #logged)
	end)

	--- Renders a child that fails, then again; returns the hook lists of both renders.
	---@param make_it_fail fun()
	---@return string[] first
	---@return string[] second
	local function fail_twice(make_it_fail)
		local child = mount("UioTownBottleneck")
		make_it_fail()
		local node = child.render({ town = 7 })
		local first = hooks
		assert.is_nil(node.box.children[1])
		assert.is_true(window_tweaks.town_level_failed)
		assert.are.equal(1, #logged)
		node = child.render({ town = 7 })
		local second = hooks
		assert.is_nil(node.box.children[1])
		-- the parent's next render unmounts the child
		local parent_node = mount("UioTownLevel").render(parent_params)
		assert.are.same({ base = { entityId = 7 } }, parent_node.box.children[1])
		assert.is_nil(parent_node.box.children[2])
		return first, second
	end

	it("keeps its hooks after a text failure until the parent drops it", function()
		local level2name = town_util.level2name
		local first, second = fail_twice(function() town_util.level2name = function() error("renamed") end end)
		town_util.level2name = level2name
		assert.are.equal(6, #first)
		assert.are.same(first, second)
	end)

	it("keeps its hooks when the ratings change shape", function()
		local get_ratings = town_util.GetRatings
		local first, second = fail_twice(function() town_util.GetRatings = function() error("renamed") end end)
		town_util.GetRatings = get_ratings
		assert.are.same(first, second)
	end)

	it("keeps its hooks when a hook raises", function()
		local first, second = fail_twice(function() throwing_hook = "noise" end)
		assert.are.same({ "useRef", "traffic", "noise" }, first)
		assert.are.same(first, second)
	end)
end)
