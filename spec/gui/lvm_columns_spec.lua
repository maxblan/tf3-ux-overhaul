-- lvm_columns.lua: the Line Manager's stack of four parts becomes two columns, while ManagerWindowContent
-- renders and the player uses mouse and keyboard; every other layout passes unchanged. The base modules
-- are stand-ins (fake_react.load); the layout builtin below the wrap records what it is given.
local fake_react = require("fake_react")

local recipe ---@type string? the recipe now rendering, as react.getCurrentRecipeName gives it
local mode ---@type string the input mode, as api.util.getInputMode gives it

---@return uo.gui.lvm_columns
local function load()
	local builtin = {
		type = { Orientation = { Vertical = "V", Horizontal = "H" } },
		---@param t table
		---@return table
		Component = function(t) return { kind = "Component", p = t } end,
	}
	return fake_react.load("/ui_overhaul/gui/lvm_columns.lua", {
		["::/gui/main/builtin.lua"] = builtin,
		["::/gui/main/react.lua"] = { getCurrentRecipeName = function() return recipe end },
	}) --[[@as uo.gui.lvm_columns]]
end

---@param p table
---@return table
local function box(p) return { kind = "BoxLayout", p = p } end

describe("lvm_columns", function()
	local globals = _G ---@type table<string, any> global name -> value, of any type
	local saved = {} ---@type table<string, any> global name -> its value before the spec
	local logged ---@type string[]
	before_each(function()
		for _i, name in ipairs({ "api", "debugPrint" }) do saved[name] = globals[name] end
		recipe, mode, logged = "ManagerWindowContent", "mouse", {}
		---@param ... any
		globals.debugPrint = function(...) logged[#logged + 1] = table.concat({ ... }) end
		local mock = {
			util = { getInputMode = function() return mode end },
			type = { enum = { InputMode = { KeyboardMouse = "mouse", Gamepad = "pad" } } },
		}
		-- A partial stand-in; the cast keeps LuaLS from merging the mock's types into the global `api`.
		_G.api = mock --[[@as api]]
	end)
	after_each(function()
		for name, value in pairs(saved) do globals[name] = value end
	end)

	it("puts the lines and the line panel on the left, the vehicles on the right, the top bar above", function()
		local lvm_columns = load()
		local wrapped = lvm_columns.wrap(box)
		local node = wrapped({ children = { "top", "lines", "vehicles", "panel" } }) ---@type table the stand-in node
		assert.are.equal("V", node.p.orientation)
		assert.are.equal("top", node.p.children[1])
		local row = node.p.children[2] ---@type table
		assert.are.equal("H", row.p.orientation)
		local left, right = row.p.children[1], row.p.children[2] ---@type table, table
		assert.are.same({ "Component", "uio-lvm-left", "V" }, { left.kind, left.p.meta.class, left.p.layout.p.orientation })
		assert.are.same({ "lines", "panel" }, left.p.layout.p.children)
		assert.are.same({ "Component", "uio-lvm-right" }, { right.kind, right.p.meta.class })
		assert.are.same({ "vehicles" }, right.p.layout.p.children)
	end)

	it("passes every other layout unchanged", function()
		local lvm_columns = load()
		local wrapped = lvm_columns.wrap(box)
		local four = { children = { 1, 2, 3, 4 } }
		recipe = "LineManagerPanel" -- another recipe
		assert.are.equal(four, wrapped(four).p)
		recipe = "ManagerWindowContent"
		local three = { children = { 1, 2, 3 } }
		assert.are.equal(three, wrapped(three).p)
		local turned = { orientation = "V", children = { 1, 2, 3, 4 } }
		assert.are.equal(turned, wrapped(turned).p)
		local classed = { meta = { class = "x" }, children = { 1, 2, 3, 4 } }
		assert.are.equal(classed, wrapped(classed).p)
		local child = { child = 1 }
		assert.are.equal(child, wrapped(child).p)
	end)

	it("keeps the parts stacked with a gamepad, which moves between them in their order", function()
		local lvm_columns = load()
		local stack = { children = { 1, 2, 3, 4 } }
		mode = "pad"
		assert.are.equal(stack, lvm_columns.wrap(box)(stack).p)
	end)

	it("arranges the columns before the first input too, when the mode is still undefined", function()
		local lvm_columns = load()
		mode = "undefined"
		local wrapped = lvm_columns.wrap(box)
		local node = wrapped({ children = { "top", "lines", "vehicles", "panel" } }) ---@type table the stand-in node
		assert.are.equal("V", node.p.orientation)
		assert.are.equal(2, #node.p.children)
	end)

	it("hands a ref and its params on unchanged", function()
		local lvm_columns = load()
		local seen ---@type table
		---@param ... any
		---@return table
		local function base(...)
			seen = table.pack(...)
			return {}
		end
		local ref, stack = { is_react_ref_info = true }, { children = { 1, 2, 3, 4 } }
		lvm_columns.wrap(base)(ref, stack)
		assert.are.same({ ref, stack, n = 2 }, seen)
	end)

	it("keeps the parts stacked and logs once when arranging them fails", function()
		local lvm_columns = load()
		lvm_columns.arrange = function() error("broken") end
		local stack = { children = { 1, 2, 3, 4 } }
		assert.are.equal(stack, lvm_columns.wrap(box)(stack).p)
		assert.are.equal(1, #logged)
	end)
end)
