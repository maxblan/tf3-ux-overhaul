--- Wrapping a builtin widget (builtin.Slider, builtin.TextView, builtin.Window ...) safely.
-- Base recipes look builtins up in the module table when they render, so replacing a field reaches
-- every use. But recipes can also be registered as wrappers of a builtin
-- (react.RegisterWrapperRecipe(name, builtin.X, fn)); one registered after the field is replaced gets
-- the replacement, which the framework does not know as a builtin, and the game crashes when it
-- renders (observed in game with builtin.Window). This module replaces the field and records the
-- replacement, and wraps react.RegisterWrapperRecipe once so it always registers against the base
-- builtin. Several wraps of the same builtin chain. GUI state, before the UI starts.
-- @module ui_overhaul.gui.builtin_wraps
local builtin = require("::/gui/main/builtin.lua")
local react = require("::/gui/main/react.lua")

---@class uo.gui.builtin_wraps
local builtin_wraps = {}

-- builtins differ in their params, so they are plain functions here
local base_of = {} ---@type table<function, function> replacement function -> the function it replaced
local registration_wrapped = false
-- the builtin module looked up by a field name only known at run time
local builtin_by_name = builtin --[[@as table<string, function?>]]

--- The base builtin behind `fn` (following chained replacements), or `fn` itself.
---@param fn function
---@return function
function builtin_wraps.base(fn)
	local seen = 0
	while base_of[fn] ~= nil and seen < 32 do
		fn, seen = base_of[fn], seen + 1
	end
	return fn
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

--- Replaces builtin[`name`] by make(base), where base is the current function. Returns base.
---@param name string the builtin's field, e.g. "Window"
---@param make fun(base: function): function
---@return function base
function builtin_wraps.wrap(name, make)
	local base = builtin_by_name[name]
	if type(base) ~= "function" then error("builtin." .. tostring(name) .. " not found") end
	wrap_registration()
	local replacement = make(base)
	base_of[replacement] = base
	builtin_by_name[name] = replacement
	return base
end

return builtin_wraps
