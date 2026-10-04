-- window_tweaks.lua: remembered entity-window sections chain on the base function and still collapse
-- for Modify; the town level text lives in a child recipe that the base card drops after a failure. The
-- base modules are stand-ins (restored after loading, so other specs keep theirs).
local registered = {}

-- Lua copy of the base function (content_card.tl:457-477)
local function base_collapsible(state, only_one_expandable)
	local function update(key, expanded)
		local prev = {}
		for k, v in pairs(state:old()) do prev[k] = v end
		if only_one_expandable then
			for k in pairs(prev) do prev[k] = false end
		end
		prev[key] = expanded
		state:set(prev)
	end
	local function is_expanded(key) return state:old()[key] == true end
	return update, is_expanded
end

local content_card = {
	makeContentCardsCollapsibleFunctions = base_collapsible,
	makeRecipeAndParam = function(recipe, param) return { recipe = recipe, param = param } end,
}
local engine_react_util = {}
local town_util = {
	GetRatings = function()
		return { { name = "Traffic", getRatingFnName = "traffic" }, { name = "Noise", getRatingFnName = "noise" } }
	end,
	level2name = function(level) return "Level " .. level end,
}

local stand_ins = {
	["::/gui/main/react.lua"] = {
		-- as in the game, calling a recipe makes a node; its body runs later, in its own instance
		RegisterRecipe = function(name, fn)
			registered[name] = fn
			return function(p) return { recipe = name, params = p } end
		end,
	},
	["::/gui/main/builtin.lua"] = {
		BoxLayout = function(t) return { box = t } end,
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

local saved = {}
for path, module in pairs(stand_ins) do
	saved[path] = package.loaded[path]
	package.loaded[path] = module
end
local window_tweaks = require("/ui_overhaul/gui/window_tweaks.lua")
for path in pairs(stand_ins) do package.loaded[path] = saved[path] end

-- A window's useState({}): set() takes effect on the next render, as in the game.
local function new_window()
	local state = { value = {}, pending = nil }
	function state:old() return self.value end
	function state:set(v) self.pending = v end
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
local previous_patch_calls = {}
local before = content_card.makeContentCardsCollapsibleFunctions
content_card.makeContentCardsCollapsibleFunctions = function(state, only_one)
	previous_patch_calls[#previous_patch_calls + 1] = only_one
	return before(state, only_one)
end
window_tweaks.install({ ReplaceRecipe = function() end })

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

describe("window_tweaks town level", function()
	local saved_globals = {}
	local logged
	local hooks -- hook calls in the current render
	local level_state
	local throwing_hook -- parallel function name whose hook raises

	before_each(function()
		for _i, name in ipairs({ "api", "_", "debugPrint" }) do saved_globals[name] = _G[name] end
		_G._ = function(text) return text end
		logged = {}
		_G.debugPrint = function(...) logged[#logged + 1] = table.concat({ ... }) end
		_G.api = {
			engine = { getComponent = function() return { developmentActive = true } end },
			type = { ComponentType = { TOWN = 1 } },
			util = { toStringPercent = function(f) return tostring(math.floor(f * 100 + 0.5)) .. "%" end },
		}
		level_state = { experience = 2.5 }
		throwing_hook = nil
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
		for name, value in pairs(saved_globals) do _G[name] = value end
		window_tweaks.town_level_failed = false
	end)

	-- One mounted instance of a recipe: refs persist across its renders; `hooks` lists the hook calls
	-- of the last render.
	local function mount(name)
		local refs, index = {}, 0
		local react = stand_ins["::/gui/main/react.lua"]
		local instance = {}
		function instance.render(params)
			hooks, index = {}, 0
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

	local inner = function(p) return { base = p } end
	local parent_params = { inner = inner, innerParam = { entityId = 7 } }

	local function text_of(node)
		local child = node.box.children[1]
		return child and child.text
	end

	it("declares no hooks in the replacement and puts the text in a keyed child", function()
		local parent = mount("UioTownLevel")
		local node = parent.render(parent_params)
		assert.are.same({}, hooks)
		assert.are.same({ base = { entityId = 7 } }, node.box.children[1])
		local child = node.box.children[2]
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
