-- tool_stack.lua: the replacement provides the api of the stack it shows (the game pushes through a ref
-- to it), keeps the vanilla stack's settings, and falls back to the vanilla stack for the session
-- without a recipe changing its hooks.
local fake_react = require("fake_react")

local fake = fake_react.new()
local builtin = fake_react.any()
builtin.BoxLayout = function(t) return { layout = t } end
builtin.ToolStack = fake.react.RegisterRecipe("ToolStack", function() end) -- the vanilla stack
local tool_stack = fake_react.load("/ui_overhaul/gui/tool_stack.lua", {
	["::/gui/main/react.lua"] = fake.react,
	["::/gui/main/builtin.lua"] = builtin,
})
local PARENT_HOOKS = { "useState", "onStep", "useRef", "useRef" }
-- registered: the vanilla stack, ToolStackEntryWrap, the mod's stack (child), the replacement
local child_recipe = fake.recipe("ToolStack", 2)
local parent_recipe = fake.recipe("ToolStack", 3)

describe("tool_stack", function()
	local saved_debug_print = _G.debugPrint
	before_each(function() _G.debugPrint = function() end end)
	after_each(function() _G.debugPrint = saved_debug_print end)

	it("replaces the vanilla stack", function()
		local calls = {}
		tool_stack.install({ ReplaceRecipe = function(old, new) calls[#calls + 1] = { old, new } end })
		assert.are.same({ { builtin.ToolStack, parent_recipe } }, calls)
	end)

	it("provides the shown stack's api and the vanilla settings, then falls back for the session", function()
		local parent = fake.mount(parent_recipe)
		local params = { defaultTool = nil, rendererComponent = { hasExpired = function() return true end } }
		local node = parent.render(params)
		assert.are.same(PARENT_HOOKS, parent.hooks)
		assert.are.same({ "ToolStack" }, parent.internals.setName)
		assert.are.same({ true }, parent.internals.setMouseTransparent)
		assert.are.same({ true }, parent.internals.setDisableFocusable)
		local child_node = node.layout.children[1]
		assert.are.equal(child_recipe, child_node.recipe)

		-- the mod's stack renders, with its hooks, and its api reaches the game through the parent
		local child = fake.render_node(child_node)
		local hooks = child.hooks
		assert.is_true(#hooks > 0)
		child_node.ref:set({ getApi = function() return child.api end })
		assert.is_nil(parent.api.getActiveTool()) -- the mod's stack is empty

		-- a failing render (no tool context) keeps the child's hooks
		child.slots[1].value = { { toolDef = {}, key = 1 } } -- an entry without its context: rendering fails
		child.render(params)
		assert.are.same(hooks, child.hooks)
		assert.is_true(tool_stack.switch.failed)

		parent.step()
		node = parent.render(params)
		assert.are.same(PARENT_HOOKS, parent.hooks)
		local base_node = node.layout.children[1]
		assert.are.equal(builtin.ToolStack, base_node.original)
		assert.are.equal(params, base_node.args[1])
		local pushed
		base_node.ref:set({ getApi = function() return { push = function(...) pushed = { ... } end } end })
		parent.api.push("tool", 1)
		assert.are.same({ "tool", 1 }, pushed)
	end)
end)
