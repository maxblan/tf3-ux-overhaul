-- sliders.lua: which builtin.Slider calls get the additions, and a call outside a recipe render stays
-- the base call, and a failed render declares the same hooks. The base modules it requires are
-- stand-ins, restored after loading so other specs keep theirs.
---@type string?
local current_recipe -- nil: no recipe is rendering
-- the replacement installed for builtin.Slider: builtin call arguments in, a node or the base's result out
---@type fun(...: any): any
local wrapped
---@type any[][] the arguments of each base slider call, as the caller passed them
local base_calls = {}
---@param ... any whatever the caller passed
---@return string
local function base_slider(...)
	base_calls[#base_calls + 1] = { ... }
	return "base"
end
-- debugPrint while the specs run: the install line stays out of the output
local function quiet() end
---@type table<string, table|function>
local stand_ins = {
	["::/gui/main/builtin.lua"] = {},
	["::/gui/main/react.lua"] = {
		---@param _name string
		---@param fn function
		---@return fun(p: any): { recipe: function, param: any } the recipe's node keeps its params, of any shape
		RegisterRecipe = function(_name, fn) return function(p) return { recipe = fn, param = p } end end,
		-- as react.lua: asserts when no recipe is rendering
		---@return string
		getCurrentRecipeName = function()
			assert(current_recipe ~= nil)
			return current_recipe
		end,
	},
	["::/gui/main/script_param_util.tl"] = {},
	["::/scripts/lang_util.tl"] = {},
	["ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua"] = {
		---@param _name string
		---@param make fun(base: function): fun(...: any): any
		wrap = function(_name, make) wrapped = make(base_slider) end,
	},
}
-- the loaded modules, of the paths above: tables and functions
---@type table<string, table|function|nil>
local loaded = package.loaded
---@type table<string, table|function|nil>
local saved = {}
for path, module in pairs(stand_ins) do
	saved[path] = loaded[path]
	loaded[path] = module
end
local sliders = require("/ui_overhaul/gui/sliders.lua")
for path in pairs(stand_ins) do loaded[path] = saved[path] end

describe("sliders", function()
	---@type fun(...: any)
	local saved_print
	before_each(function()
		saved_print = _G.debugPrint
		_G.debugPrint = quiet
		sliders.install({})
	end)
	after_each(function() _G.debugPrint = saved_print end)

	it("enhances plain sliders outside the settings menu", function()
		local p = { onValueChange = function() end }
		assert.is_true(sliders.enhance({ p }, "LinePlugin"))
		assert.is_false(sliders.enhance({ p }, "SettingsPage"))
		assert.is_false(sliders.enhance({ { uioPlain = true, onValueChange = p.onValueChange } }, "LinePlugin"))
		assert.is_false(sliders.enhance({ {} }, "LinePlugin"))
	end)

	it("renders the enhanced slider while a recipe renders", function()
		current_recipe = "LinePlugin"
		local node = wrapped({ onValueChange = function() end })
		assert.are.equal("table", type(node))
		assert.are.equal("function", type(node.recipe))
	end)

	it("passes a call outside a recipe render to the base slider", function()
		current_recipe = nil
		base_calls = {}
		local p = { onValueChange = function() end }
		assert.are.equal("base", wrapped(p))
		assert.are.equal(1, #base_calls)
		assert.are.equal(p, base_calls[1][1])
	end)
end)

describe("sliders hooks", function()
	local fake_react = require("fake_react")
	local fake = fake_react.new()
	---@type uo.sliders.SliderParam the params of the last base slider call
	local base
	local builtin = fake_react.any()
	builtin.BoxLayout = function(t) return { layout = t } end
	local module = fake_react.load("/ui_overhaul/gui/sliders.lua", {
		["::/gui/main/react.lua"] = fake.react,
		["::/gui/main/builtin.lua"] = builtin,
		["ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua"] = {
			---@param _name string
			---@param make fun(base: fun(p: uo.sliders.SliderParam): table)
			wrap = function(_name, make) make(function(p) base = p return { slider = p } end) end,
		},
	})
	---@type fun(...: any)
	local saved_print
	before_each(function()
		saved_print = _G.debugPrint
		_G.debugPrint = quiet
		module.install({})
	end)
	after_each(function() _G.debugPrint = saved_print end)

	it("declares the same hooks when a render fails and the base slider shows", function()
		-- onMouseEvent sets a component internal; kept with the hooks all the same
		local slider = fake.mount(fake.recipe("UioSlider"))
		local p = { min = 0, max = 10, step = 1, value = 3, onValueChange = function() end }
		slider.render({ p = p })
		local hooks = slider.hooks
		assert.are.same({ "useState", "useState", "useRef", "useRef", "onMouseEvent" }, hooks)
		p.step = "one" -- fails after the hooks and the mouse listener
		local node = slider.render({ p = p })
		assert.are.same(hooks, slider.hooks)
		assert.are.equal(p, base)
		assert.are.same({ slider = p }, node.layout.children[1])
	end)

	it("falls back to a plain slider without raising on odd value lists", function()
		local row = fake.mount(fake.recipe("ScriptParamSliderAndText"))
		---@type string? the value list holds strings here, on purpose
		local sent
		local param = { scriptParam = { numbers = { "a", "b" } }, currentValue = 0,
			onValueChange = function(v) sent = v end }
		local node = row.render(param)
		local hooks = row.hooks
		assert.are.same({ "useState", "useState", "useRef", "useState", "useRef", "useRef", "onMouseEvent" }, hooks)
		assert.are.same({ value = 1, min = 1, max = 2, step = 1 },
			{ value = base.value, min = base.min, max = base.max, step = base.step })
		assert.are.equal(base, node.layout.children[1].slider)
		base.onValueChange(2)
		assert.are.equal("b", sent)
		param.scriptParam = {} -- no list at all
		row.render(param)
		assert.are.same(hooks, row.hooks)
		assert.are.same({ 1, 1 }, { base.value, base.max })
	end)
end)
