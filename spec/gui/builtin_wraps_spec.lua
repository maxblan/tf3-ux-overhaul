-- builtin_wraps.lua: wrapped builtins, and window recipes registered afterwards still wrap the base.
local registered = {} ---@type table<string, function> recipe name -> the builtin it wraps
local base_window = function(p) return { window = p } end
local base_slider = function(p) return { slider = p } end
-- the framework's table of registered recipes, under the name react.lua gives it (builtin_wraps finds
-- it as an upvalue of GetRecipeId)
local recipeFnToRecipeId = { [base_window] = 1, [base_slider] = 2 } ---@type table<function, integer>
---@type table<string, table> module path -> stand-in
local stand_ins = {
	["::/gui/main/builtin.lua"] = { Window = base_window, Slider = base_slider },
	["::/gui/main/react.lua"] = {
		RegisterWrapperRecipe = function(name, wrapped, fn)
			registered[name] = wrapped
			return fn
		end,
		---@param fn function
		---@return integer?
		GetRecipeId = function(fn) return recipeFnToRecipeId[fn] end,
		---@param fn function
		---@return string?
		GetRecipeName = function(fn) return recipeFnToRecipeId[fn] and "builtin" .. recipeFnToRecipeId[fn] or nil end,
	},
}
local loaded = package.loaded ---@type table<string, any> module name -> module, of any type
local saved = {} ---@type table<string, any> module path -> what package.loaded held: any module
for path, module in pairs(stand_ins) do
	saved[path] = loaded[path]
	loaded[path] = module
end
local builtin_wraps = dofile("src/ui_overhaul/content/ui_overhaul/gui/builtin_wraps.lua")
local builtin = stand_ins["::/gui/main/builtin.lua"]
local react = stand_ins["::/gui/main/react.lua"]
for path in pairs(stand_ins) do loaded[path] = saved[path] end

describe("builtin_wraps", function()
	it("replaces a builtin and keeps later wrapper recipes on the base", function()
		local first = builtin_wraps.wrap("Window", function(base)
			---@param p table
			---@return table
			return function(p)
				local r = base(p) ---@type table the stand-in's node
				r.first = true
				return r
			end
		end)
		assert.are.equal(base_window, first)
		builtin_wraps.wrap("Window", function(base)
			---@param p table
			---@return table
			return function(p)
				local r = base(p) ---@type table the stand-in's node
				r.second = true
				return r
			end
		end)
		local node = builtin.Window({ title = "x" }) ---@type table the stand-in's node
		assert.is_true(node.first and node.second)
		-- a window recipe registered now gets the base builtin, not a replacement
		react.RegisterWrapperRecipe("LateWindow", builtin.Window, function() end)
		assert.are.equal(base_window, registered.LateWindow)
		assert.are.equal(base_window, builtin_wraps.base(builtin.Window))
	end)

	it("answers recipe id and name of a replaced builtin as the builtin's (Town Zoning Tool looks them up)", function()
		assert.is_false(base_window == builtin.Window)
		assert.are.equal(1, react.GetRecipeId(builtin.Window))
		assert.are.equal("builtin1", react.GetRecipeName(builtin.Window))
		assert.are.equal(1, react.GetRecipeId(base_window))
		assert.is_nil(react.GetRecipeId(function() end))
	end)

	it("unwinds past another mod's plain wrap, above or below this module's", function()
		-- above: another mod wraps the field after this module did
		local foreign_above = function(p) return builtin_wraps.base(base_window)(p) end
		local ours = builtin.Window
		builtin.Window = foreign_above
		react.RegisterWrapperRecipe("AboveWindow", builtin.Window, function() end)
		assert.are.equal(base_window, registered.AboveWindow)
		builtin.Window = ours
		-- below: another mod wrapped the field before this module's first wrap of it
		local globals = _G ---@type table<string, any> global name -> value, of any type
		local saved_react = globals._react
		globals._react = { builtin = { Slider = 2 } }
		builtin.Slider = function(p) return base_slider(p) end
		builtin_wraps.wrap("Slider", function(base) return function(p) return base(p) end end)
		globals._react = saved_react
		react.RegisterWrapperRecipe("SliderRecipe", builtin.Slider, function() end)
		assert.are.equal(base_slider, registered.SliderRecipe)
	end)

	it("refuses a builtin that does not exist", function()
		assert.is_false(pcall(builtin_wraps.wrap, "NoSuchWidget", function(base) return base end))
	end)
end)
