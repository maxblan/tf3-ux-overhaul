-- Minimize (gui/minimize.lua): the title row in the window's header slot (title, rename, minimize),
-- the fold state per window instance in window wrapper recipes, and the fold state of windows that
-- share a key. The base modules are stand-ins (fake_react.load).
local fake_react = require("fake_react")

---@class spec.MinimizeNode
---@field kind string
---@field p spec.MinimizeParams

---The params of the builtins the title row is made of, the fields the specs read.
---@class spec.MinimizeParams
---@field children spec.MinimizeNode[]
---@field text? string
---@field value? string
---@field meta react.Meta
---@field onClick fun()
---@field onValueChange fun(value: string)

---@param kind string
---@return fun(a: any, b: any): spec.MinimizeNode
local function made(kind)
	-- called as builtin(params) or builtin(ref, params)
	return function(a, b) return { kind = kind, p = b or a } end
end

---@return spec.Fake fake
---@return uo.gui.minimize minimize
---@return fun(p: any): any window the wrapped builtin.Window; returns the params the base got
local function load()
	local fake = fake_react.new()
	local react = fake.react --[[@as table<string, any>]] -- the fake has no fireEvent
	react.fireEvent = function() end
	local builtin = fake_react.any() ---@type table<string, any>
	for _i, kind in ipairs({ "BoxLayout", "TextView", "TextInputField", "Button", "ImageView", "Component" }) do
		builtin[kind] = made(kind)
	end
	local make_window ---@type fun(base: function): function
	local minimize = fake_react.load("/ui_overhaul/gui/minimize.lua", {
		["::/gui/main/react.lua"] = fake.react,
		["::/gui/main/builtin.lua"] = builtin,
		["ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua"] = {
			---@param _name string
			---@param make fun(base: function): function
			wrap = function(_name, make) make_window = make end,
		},
	}) --[[@as uo.gui.minimize]]
	minimize.install(fake_react.any())
	return fake, minimize, make_window(function(p) return p end)
end

---@param title? string
---@return table<string, any>
local function finances(title)
	return { title = title or "Falcon Transport", closable = true, content = { "charts" }, titleEditable = true,
		id = "menu.finance.window", meta = { class = "own" } }
end

describe("minimize", function()
	local globals = _G ---@type table<string, any> global name -> value, of any type
	local saved = {} ---@type table<string, any>
	before_each(function()
		for _i, name in ipairs({ "debugPrint", "_", "_react" }) do saved[name] = globals[name] end
		globals.debugPrint = function() end
		---@param text string
		---@return string
		globals._ = function(text) return text end
		globals._react = nil
	end)
	after_each(function()
		for _i, name in ipairs({ "debugPrint", "_", "_react" }) do globals[name] = saved[name] end
	end)

	it("puts the title row in the header and switches the engine's title and rename off", function()
		local _fake, _minimize, window = load()
		local p = window(finances())
		assert.is_false(p.titleEditable)
		assert.are.equal("own, uio-minimizable", p.meta.class)
		assert.are.equal("UioWindowHeader", p.header.name)
		local header = p.header.args[1] ---@type table<string, any>
		assert.are.same({ "id:menu.finance.window", "Falcon Transport", true },
			{ header.key, header.title, header.editable })
		assert.are.equal("UioMinimizable", p.content.name)
		-- a window with its own header, or without a close button, stays as it is
		local own = { title = "x", closable = true, content = {}, header = {} }
		assert.are.equal(own, window(own))
	end)

	it("gives the Line Manager, which has no title bar, a title row of its own above its content", function()
		local _fake, _minimize, window = load()
		local manager = { compact = true, closable = true, tool = "management", id = "menu.management",
			content = { "lines" } }
		local p = window(manager)
		assert.is_nil(p.header) -- a compact window draws no header slot
		local rows = p.content.p.children ---@type spec.MinimizeNode[]
		assert.are.same({ "Component", "uio-compact-header" }, { rows[1].kind, rows[1].p.meta.class })
		-- a Component's layout must be a layout builtin (a recipe there crashes the game natively)
		local layout = rows[1].p.layout --[[@as spec.MinimizeNode]]
		assert.are.equal("BoxLayout", layout.kind)
		local recipe_node = layout.p.children[1] --[[@as { args: table<string, any>[] }]]
		local header = recipe_node.args[1]
		assert.are.same({ "Line Manager", false }, { header.title, header.editable })
		local content = rows[2] --[[@as { name: string, args: table<string, any>[] }]]
		assert.are.same({ "UioMinimizable", "uio.minimize.menu.management" }, { content.name, content.args[1].id })
		-- other compact windows (Statistics: the game's own minimize) stay as they are
		local statistics = { compact = true, closable = true, tool = "Statistics", content = {} }
		assert.are.equal(statistics, window(statistics))
	end)

	it("renames through its own field and keeps its hooks", function()
		local fake, _minimize, window = load()
		local renamed = {} ---@type string[]
		local p = finances()
		p.onTitleChange = function(title) renamed[#renamed + 1] = title end
		local header = fake.mount(fake.recipe("UioWindowHeader"))
		local params = window(p).header.args[1] ---@type uo.minimize.WindowHeaderParams
		local row = header.render(params) ---@type spec.MinimizeNode
		local hooks = header.hooks
		local children = row.p.children
		local title, rename, minimize_button = children[1], children[2], children[3]
		assert.are.same({ "TextView", "Falcon Transport" }, { title.kind, title.p.text })
		assert.are.equal("Button", rename.kind)
		assert.are.equal("Minimize", minimize_button.p.meta.tooltip)
		rename.p.onClick()
		row = header.render(params)
		assert.are.same(hooks, header.hooks)
		local field = row.p.children[1] ---@type spec.MinimizeNode
		assert.are.same({ "TextInputField", "Falcon Transport" }, { field.kind, field.p.value })
		field.p.onValueChange("Falcon Freight")
		assert.are.same({ "Falcon Freight" }, renamed)
		row = header.render(params)
		assert.are.equal("TextView", row.p.children[1].kind)
	end)

	it("keeps an empty name out where the window does not allow it", function()
		local fake, _minimize, window = load()
		local renamed = 0
		local p = finances()
		p.emptyNameAllowed = false
		p.onTitleChange = function() renamed = renamed + 1 end
		local header = fake.mount(fake.recipe("UioWindowHeader"))
		local params = window(p).header.args[1] ---@type uo.minimize.WindowHeaderParams
		local row = header.render(params) ---@type spec.MinimizeNode
		row.p.children[2].p.onClick()
		row = header.render(params)
		row.p.children[1].p.onValueChange("")
		assert.are.equal(0, renamed)
	end)

	it("a window that cannot be renamed has no rename button", function()
		local fake, _minimize, window = load()
		local p = finances()
		p.titleEditable = nil
		local header = fake.mount(fake.recipe("UioWindowHeader"))
		local row = header.render(window(p).header.args[1]) ---@type spec.MinimizeNode
		assert.are.equal(2, #row.p.children)
	end)

	it("keys windows of a window wrapper recipe per instance, with the same hooks on every render", function()
		local fake, _minimize, window = load()
		globals._react = { builtin = { Window = 1 }, recipeMetas = { [7] = { innerRecipeId = 1 } } }
		local react = fake.react --[[@as table<string, any>]] -- the fake has no getCurrentRecipeId
		react.getCurrentRecipeId = function() return 7 end
		local recipe = fake.react.RegisterRecipe("FinancesWindow", function(p) return window(p) end)
		local first, second = fake.mount(recipe), fake.mount(recipe)
		local a = first.render(finances("Settings")).header.args[1].key ---@type string
		local b = second.render(finances("Settings")).header.args[1].key ---@type string
		assert.is_true(a ~= b)
		local hooks = first.hooks ---@type string[]
		assert.are.same({ "useRef", "useState", "onEvent:uio.minimize" }, hooks)
		-- not eligible this time (no title yet): the same hooks, the window untouched
		local untitled = finances("")
		assert.are.equal(untitled, first.render(untitled))
		assert.are.same(hooks, first.hooks)
		assert.are.equal(a, first.render(finances("Settings")).header.args[1].key)
	end)

	it("a key shared by two open windows stays folded until the last one closes", function()
		local fake, minimize = load()
		local one, two = fake.mount(fake.recipe("UioMinimizable")), fake.mount(fake.recipe("UioMinimizable"))
		for _i, instance in ipairs({ one, two }) do
			instance.render({ key = "title:Settings" })
			for _j, fn in ipairs(instance.on_mount) do fn() end
		end
		minimize.toggle("title:Settings")
		one.unmount()
		assert.is_true(minimize.is_minimized("title:Settings"))
		two.unmount()
		assert.is_false(minimize.is_minimized("title:Settings"))
	end)
end)
