--- Failure isolation for the mod's GUI. An error that escapes a recipe, or a module that fails to
-- load, makes the engine drop the *whole* game UI (observed in-game). So every plugin recipe the
-- engine sees is a thin stub (see *.script.lua) that loads the real implementation and renders it
-- through guard.call: on any error the mod's widget renders nothing and logs one line, and the rest
-- of the game UI keeps working.
-- It also holds the small helpers the GUI modules share: a report-once logger, a guarded clock and
-- a shallow copy.
-- Loads no module itself until a fallback is rendered (builtin.lua), so any file can use it.
-- @module ui_overhaul.gui.guard

---@class uo.gui.guard
local guard = {}

--- A logger that writes one line per key, the first time the key fails:
-- "[ui_overhaul] <prefix><key><separator><error>".
---@param prefix string e.g. "catchment: "
---@param separator? string between the key and the error, default ": "
---@return fun(key: string, err: any) report err: what pcall caught, any Lua value
function guard.reporter(prefix, separator)
	separator = separator or ": "
	local reported = {} ---@type table<string, true>
	return function(key, err)
		if reported[key] then return end
		reported[key] = true
		debugPrint("[ui_overhaul] ", prefix, key, separator, tostring(err))
	end
end

local report = guard.reporter("disabled ")

--- Seconds of processor time (os.clock), or nil where the game's Lua offers no clock.
---@return number?
function guard.clock()
	local ok, t = pcall(os.clock)
	return ok and type(t) == "number" and t or nil
end

--- A copy of `t` with the same fields and values.
---@generic T: table
---@param t T
---@return T
function guard.shallow_copy(t)
	local copy = {}
	-- LuaLS cannot infer pairs()'s key and value types for a generic table
	---@diagnostic disable-next-line: no-unknown
	for k, v in pairs(t) do copy[k] = v end
	return copy
end

--- An empty layout: the safe result of a failed plugin recipe.
---@return react.TreeNodeId
function guard.empty()
	local builtin = require("::/gui/main/builtin.lua")
	return builtin.BoxLayout{}
end

local report_original = guard.reporter("base recipe ")

---Safe calls of one base recipe (guard.base).
---@class uo.gui.guard.Base
---@field node fun(...: any): react.TreeNodeId? its node, or nil where it makes none or raises
---@field layout fun(...: any): react.TreeNodeId its node inside a layout (a recipe has to return one), empty without

--- Safe calls of the base recipe `recipe`, for a replacement that shows it: react.CallOriginalRecipe in
-- pcall, and nothing where it makes no node or raises (one log line). Call this while the module
-- loads, with the recipe the base module holds then: another mod may later put a plain function in
-- that field, which the framework does not know as a recipe, so CallOriginalRecipe would raise for it
-- (and an error that escapes a recipe drops the whole game UI).
---@param name string for the log line
---@param recipe function the base recipe
---@return uo.gui.guard.Base
function guard.base(name, recipe)
	-- while a module loads, base paths resolve (in the specs: to their stand-ins)
	local react = require("::/gui/main/react.lua")
	local builtin = require("::/gui/main/builtin.lua")
	---@param ... any the recipe's arguments (a ref first, then its params), passed on unchanged
	---@return react.TreeNodeId?
	local function node(...)
		local ok, result = pcall(react.CallOriginalRecipe, recipe, ...)
		if ok then return result end
		report_original(name, result)
		return nil
	end
	---@param ... any the recipe's arguments, passed on unchanged
	---@return react.TreeNodeId
	local function layout(...)
		local result = node(...)
		return builtin.BoxLayout{ children = result ~= nil and { result } or {} }
	end
	return { node = node, layout = layout }
end

-- A module that failed to load is not loaded again: each attempt reads the file anew, and the
-- game's loader (base/init.lua) pushes the path onto its require stack and changes the current mod
-- before it runs the file, and undoes neither when loading fails. Both are put back here, so a later
-- relative require still resolves where it should.
local failed = {} ---@type table<string, true>

--- Loads a module with pcall; nil (and one log line) if it fails. `path` must be fully qualified
-- ("ui_overhaul_1::/..."): a mod-relative "/..." path only resolves to the owning mod while a module
-- is being loaded; at render time it resolves to the base game (observed in-game).
---@param path string
---@return table? module the module's own table, its shape depends on `path`
function guard.module(path)
	if failed[path] then return nil end
	-- rawget and rawset are not there in the game's GUI state (observed in game); a plain read of a
	-- global the game may not define goes through pcall, in case a strict-globals check refuses it
	local globals = _G --[[@as table<string, any>]]
	local stack, mod_id ---@type any, any the loader's own globals, whatever they hold
	if not pcall(function() stack, mod_id = globals._ug_filePathRequireStack, globals._currentModIdTr end) then
		stack, mod_id = nil, nil
	end
	local depth = type(stack) == "table" and #stack or nil
	local ok, module = pcall(require, path)
	if ok then return module end
	failed[path] = true
	if depth then
		---@cast stack string[]
		while #stack > depth do table.remove(stack) end
		pcall(function() globals._currentModIdTr = mod_id end)
	end
	report(path, module)
	return nil
end

--- Calls module[field](...) safely. Returns its result, or `fallback()` (default: an empty layout)
-- if the module or the call fails.
---@param path string
---@param field string
---@param fallback? fun(): any
---@param ... any passed on to module[field] unchanged
---@return any result what module[field] (looked up by name at run time) or `fallback` returns
function guard.call(path, field, fallback, ...)
	fallback = fallback or guard.empty
	local module = guard.module(path)
	local fn = module and module[field]
	if type(fn) ~= "function" then
		if module then report(path .. "@" .. field, "no such function") end
		return fallback()
	end
	local ok, result = pcall(fn, ...)
	if ok then return result end
	report(path .. "@" .. field, result)
	return fallback()
end

--- Recipe function for a plugin of an ordinary extension point: renders module[field](params).
-- With `feature`: an empty layout while that feature is not shown (switched off in the mod's settings,
-- or given up to a mod that comes first in the mod list, priority.lua). That is decided before the UI
-- starts, so a plugin never changes between rendering and not rendering its hooks.
---@param path string
---@param field string
---@param feature? string
---@return fun(...: any): react.TreeNodeId recipe its params are the plugin's, passed on unchanged
function guard.plugin(path, field, feature)
	if feature == nil then
		return function(...) return guard.call(path, field, nil, ...) end
	end
	-- loaded on the first render, then kept (a module that fails to load is not tried again)
	local priority, settings ---@type uo.gui.priority?, uo.gui.settings?
	return function(...)
		priority = priority or guard.module("ui_overhaul_1::/ui_overhaul/gui/priority.lua") --[[@as uo.gui.priority?]]
		settings = settings or guard.module("ui_overhaul_1::/ui_overhaul/gui/settings.lua") --[[@as uo.gui.settings?]]
		if priority == nil or settings == nil or not settings.enabled(feature) or not priority.active(feature) then
			return guard.empty()
		end
		return guard.call(path, field, nil, ...)
	end
end

return guard
