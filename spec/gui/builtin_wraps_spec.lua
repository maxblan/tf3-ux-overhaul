-- builtin_wraps.lua: wrapped builtins, and window recipes registered afterwards still wrap the base.
local registered = {}
local base_window = function(p) return { window = p } end
local stand_ins = {
	["::/gui/main/builtin.lua"] = { Window = base_window },
	["::/gui/main/react.lua"] = {
		RegisterWrapperRecipe = function(name, wrapped, fn)
			registered[name] = wrapped
			return fn
		end,
	},
}
local saved = {}
for path, module in pairs(stand_ins) do
	saved[path] = package.loaded[path]
	package.loaded[path] = module
end
local builtin_wraps = dofile("src/ui_overhaul/content/ui_overhaul/gui/builtin_wraps.lua")
local builtin = stand_ins["::/gui/main/builtin.lua"]
local react = stand_ins["::/gui/main/react.lua"]
for path in pairs(stand_ins) do package.loaded[path] = saved[path] end

describe("builtin_wraps", function()
	it("replaces a builtin and keeps later wrapper recipes on the base", function()
		local first = builtin_wraps.wrap("Window", function(base)
			return function(p) local r = base(p) r.first = true return r end
		end)
		assert.are.equal(base_window, first)
		builtin_wraps.wrap("Window", function(base)
			return function(p) local r = base(p) r.second = true return r end
		end)
		local node = builtin.Window({ title = "x" })
		assert.is_true(node.first and node.second)
		-- a window recipe registered now gets the base builtin, not a replacement
		react.RegisterWrapperRecipe("LateWindow", builtin.Window, function() end)
		assert.are.equal(base_window, registered.LateWindow)
		assert.are.equal(base_window, builtin_wraps.base(builtin.Window))
	end)

	it("refuses a builtin that does not exist", function()
		assert.is_false(pcall(builtin_wraps.wrap, "NoSuchWidget", function(base) return base end))
	end)
end)
