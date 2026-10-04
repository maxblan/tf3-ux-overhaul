-- fallback.lua: the parent declares the same hooks on every render, the child keeps its hooks after a
-- failure, and the parent drops the child for the base on the next GUI step.
local fake_react = require("fake_react")

local fake = fake_react.new()
local builtin = { BoxLayout = function(t) return { layout = t } end }
---@type uo.gui.fallback
local fallback = fake_react.load("/ui_overhaul/gui/fallback.lua", {
	["::/gui/main/react.lua"] = fake.react,
	["::/gui/main/builtin.lua"] = builtin,
})

local BASE = fake.react.RegisterRecipe("Base", function() end)
local PARENT_HOOKS = { "useState", "onStep", "useRef", "useRef" }

describe("fallback", function()
	local saved_debug_print = _G.debugPrint
	---@type string[]
	local logged
	---@param ... any
	local function record(...) logged[#logged + 1] = table.concat({ ... }) end
	before_each(function()
		logged = {}
		_G.debugPrint = record
	end)
	after_each(function() _G.debugPrint = saved_debug_print end)

	-- A render with two hooks, then work that fails while `broken` is set.
	---@param label string
	---@return uo.gui.fallback.Switch switch
	---@return { broken: boolean } control
	---@return function parent
	local function make(label)
		local switch = fallback.switch(label)
		local control = { broken = false }
		---@param params string
		---@return react.TreeNodeId
		local parent = fallback.replacement(switch, "Thing", function(params)
			fake.react.useState(0)
			fake.react.onStep(function() end)
			if control.broken then error("boom") end
			return { content = params }
		end, BASE)
		return switch, control, parent
	end

	it("renders the child, which owns the hooks", function()
		local _switch, _control, parent = make("thing")
		local p = fake.mount(parent)
		local node = p.render("x")
		assert.are.same(PARENT_HOOKS, p.hooks)
		assert.are.same({ class = "uio-fallback" }, node.layout.meta) -- unspaced (fallback.css.lua)
		local child_node = node.layout.children[1] ---@type spec.FakeNode
		assert.are.equal("Thing", child_node.name)
		local child, content = fake.render_node(child_node)
		assert.are.same({ content = "x" }, content)
		assert.are.same({ "useState", "onStep" }, child.hooks)
	end)

	it("keeps the child's hooks after a failure and drops it on the parent's next step", function()
		local switch, control, parent = make("thing")
		local p = fake.mount(parent)
		local child = fake.render_node(p.render("x").layout.children[1])
		local hooks = child.hooks

		control.broken = true
		local empty = child.render("x")
		assert.are.same({ layout = { meta = { class = "uio-fallback" } } }, empty)
		assert.are.same(hooks, child.hooks)
		assert.is_true(switch.failed)
		assert.are.equal(1, #logged)
		control.broken = false
		assert.are.same({ layout = { meta = { class = "uio-fallback" } } }, child.render("x")) -- no switching back
		assert.are.same(hooks, child.hooks)

		-- the parent renders again on its next step, now with the base, and the same hooks
		assert.is_false(p.dirty)
		p.step()
		assert.is_true(p.dirty)
		local node = p.render("x")
		assert.are.same(PARENT_HOOKS, p.hooks)
		assert.are.equal(BASE, node.layout.children[1].original)
		assert.are.same({ "x" }, { table.unpack(node.layout.children[1].args, 1, 1) })
		assert.are.equal(1, #logged)
	end)

	it("provides the replaced recipe's api from the shown node, and its focus child", function()
		local switch = fallback.switch("api")
		local parent = fallback.replacement(switch, "WithApi", function() return {} end, BASE,
			{ api = { "push" }, focus = true, internals = function() fake.react.setName("WithApi") end })
		local p = fake.mount(parent)
		local node = p.render()
		assert.are.same(PARENT_HOOKS, p.hooks)
		assert.are.same({ "WithApi" }, p.internals.setName)
		local child_api = { push = function(x) return "child " .. x end }
		node.layout.children[1].ref:set({ getApi = function() return child_api end })
		assert.are.equal(node.layout.children[1].ref, p.internals.setPreferredFocusChild[1])
		assert.are.equal("child 1", p.api.push(1))

		fallback.fail(switch, "boom")
		-- until the base is mounted, the child's api
		assert.are.equal("child 2", p.api.push(2))
		p.step()
		node = p.render()
		assert.are.same(PARENT_HOOKS, p.hooks)
		local base_node = node.layout.children[1] ---@type spec.FakeNode
		assert.are.equal(BASE, base_node.original)
		assert.are.equal(base_node.ref, p.internals.setPreferredFocusChild[1])
		base_node.ref:set({ getApi = function() return { push = function(x) return "base " .. x end } end })
		assert.are.equal("base 3", p.api.push(3))
	end)

	it("renders an unspaced empty layout for a render that returns nothing", function()
		local switch = fallback.switch("nothing")
		local parent = fallback.replacement(switch, "Nothing", function() return nil end, BASE)
		local _child, node = fake.render_node(fake.mount(parent).render().layout.children[1])
		assert.are.same({ layout = { meta = { class = "uio-fallback" } } }, node)
	end)

	it("renders nothing where the base renders nothing, with the same hooks", function()
		local switch = fallback.switch("editor")
		local editor = true
		local parent = fallback.replacement(switch, "Editor", function() return {} end, BASE,
			{ nothing = function() return editor end })
		local p = fake.mount(parent)
		assert.is_nil(p.render())
		assert.are.same(PARENT_HOOKS, p.hooks)
		editor = false
		assert.are.equal("table", type(p.render()))
		assert.are.same(PARENT_HOOKS, p.hooks)
	end)

	it("forwards the input actions the game sends to the replaced node on to the shown node", function()
		local switch = fallback.switch("keys")
		local parent = fallback.replacement(switch, "Keys", function() return {} end, BASE,
			{ input_actions = { "IA_NOTIFICATIONS_OPEN" } })
		local p = fake.mount(parent)
		local node = p.render()
		local hooks = p.hooks
		assert.are.equal(node.layout.children[1].ref, p.input_actions.IA_NOTIFICATIONS_OPEN.forward)
		fallback.fail(switch, "boom")
		p.step()
		node = p.render()
		assert.are.same(hooks, p.hooks)
		assert.are.equal(BASE, node.layout.children[1].original)
		assert.are.equal(node.layout.children[1].ref, p.input_actions.IA_NOTIFICATIONS_OPEN.forward)
	end)
end)
