--- Wrapping a builtin widget (builtin.Slider, builtin.TextView, builtin.Window ...) safely.
-- Base recipes look builtins up in the module table when they render, so replacing a field reaches
-- every use. But recipes can also be registered as wrappers of a builtin
-- (react.RegisterWrapperRecipe(name, builtin.X, fn)); one registered after the field is replaced gets
-- the replacement, which the framework does not know as a builtin, and the game crashes when it
-- renders (observed in game with builtin.Window). This module replaces the field and records the
-- replacement, and wraps react.RegisterWrapperRecipe once so it always registers against the base
-- builtin. Several wraps of the same builtin chain. Another mod may wrap the same field in the plain
-- way, before or after this mod: the base is the registered builtin recipe, which this module
-- remembers per field, not merely the end of its own chain. GUI state, before the UI starts.
-- @module ui_overhaul.gui.builtin_wraps
local builtin = require("::/gui/main/builtin.lua")
local react = require("::/gui/main/react.lua")
local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")

---@class uo.gui.builtin_wraps
local builtin_wraps = {}

-- builtins differ in their params, so they are plain functions here
local base_of = {} ---@type table<function, function> replacement function -> the function it replaced
local builtin_of = {} ---@type table<string, function> field name -> the registered builtin recipe
local name_of = {} ---@type table<function, string> replacement function -> the field it replaced
local registration_wrapped = false
-- the builtin module looked up by a field name only known at run time
local builtin_by_name = builtin --[[@as table<string, function?>]]

-- Whether `fn` is a recipe the framework registered (a builtin, or a recipe of a mod).
---@param fn function
---@return boolean
local function is_recipe(fn)
	local ok, id = pcall(react.GetRecipeId, fn)
	return ok and id ~= nil
end

-- The registered builtin `name` when the field holds another mod's plain wrap that this module cannot
-- unwind: looked up by the builtin's recipe id in react.lua's recipe table (recipeFnToRecipeId, the
-- upvalue of GetRecipeId). nil where the debug library or the table is not there.
---@param name string
---@return function?
local function registered_builtin(name)
	local ok, found = pcall(function()
		local id = _react.builtin[name]
		if id == nil or type(debug) ~= "table" then return nil end
		-- the one table GetRecipeId keeps, found by its value: base scripts may carry no upvalue names
		local ids ---@type table<function, integer>?
		for i = 1, 16 do
			local upvalue, value = debug.getupvalue(react.GetRecipeId, i)
			if upvalue == nil then break end
			if type(value) == "table" then
				if ids then return nil end
				ids = value --[[@as table<function, integer>]]
			end
		end
		for fn, fn_id in pairs(ids or {}) do
			if fn_id == id then return fn end
		end
		return nil
	end)
	return ok and found or nil
end

-- Follows this module's chained replacements from `fn` down to a registered recipe, or to the first
-- function this module did not make. Also returns the field name of the last replacement passed.
---@param fn function
---@return function
---@return string? name
local function unwind(fn)
	local name, seen = nil, 0 ---@type string?, integer
	while not is_recipe(fn) and base_of[fn] ~= nil and seen < 32 do
		name = name or name_of[fn]
		fn, seen = base_of[fn], seen + 1
	end
	return fn, name
end

--- The base builtin behind `fn`: following this module's chained replacements to the registered
-- builtin, also past another mod's plain wrap of a field this module wrapped; `fn` itself otherwise.
---@param fn function
---@return function
function builtin_wraps.base(fn)
	local found, name = unwind(fn)
	if is_recipe(found) then return found end
	if name == nil then
		-- not one of this module's replacements: perhaps another mod's wrap now in the field
		for field, base in pairs(builtin_of) do
			if builtin_by_name[field] == fn then return base end
		end
		return fn
	end
	return builtin_of[name] or found
end

local function wrap_registration()
	if registration_wrapped then return end
	local register = react.RegisterWrapperRecipe
	if type(register) ~= "function" then error("react.RegisterWrapperRecipe not found") end
	---@param name string
	---@param wrapped function
	---@param ... any the rest of RegisterWrapperRecipe's arguments, passed on unchanged
	---@return react.RecipeN<any, any, any, any, any> recipe its params are those of the wrapping function
	react.RegisterWrapperRecipe = function(name, wrapped, ...)
		return register(name, builtin_wraps.base(wrapped), ...)
	end
	registration_wrapped = true
end

--- Replaces builtin[`name`] by make(base), where base is the current function. Returns base. The
-- replacement is a link of the feature being installed (priority.chain): once the load order is
-- decided it is make(base) itself, or base while that feature is not shown.
---@param name string the builtin's field, e.g. "Window"
---@param make fun(base: function): function
---@return function base
function builtin_wraps.wrap(name, make)
	local base = builtin_by_name[name]
	if type(base) ~= "function" then error("builtin." .. tostring(name) .. " not found") end
	wrap_registration()
	if builtin_of[name] == nil then
		local found = unwind(base)
		builtin_of[name] = (not is_recipe(found) and registered_builtin(name)) or found
	end
	---@param replacement function
	local function remember(replacement)
		base_of[replacement] = base
		name_of[replacement] = name
	end
	local installed = priority.chain(builtin, name, make, true, function(_old, new)
		-- base itself, where the feature is not shown, is base_of's already or a registered recipe
		if new ~= base then remember(new) end
	end)
	remember(installed)
	return base
end

return builtin_wraps
