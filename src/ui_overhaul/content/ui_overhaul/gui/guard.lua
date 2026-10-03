--- Failure isolation for the mod's GUI. An error that escapes a recipe, or a module that fails to
-- load, makes the engine drop the *whole* game UI (observed in-game). So every plugin recipe the
-- engine sees is a thin stub (see *.script.lua) that loads the real implementation and renders it
-- through guard.call: on any error the mod's widget renders nothing and logs one line, and the rest
-- of the game UI keeps working.
-- Depends only on base modules that every GUI file uses (builtin.lua).
-- @module ui_overhaul.gui.guard
local builtin = require("::/gui/main/builtin.lua")

local guard = {}

local reported = {}

local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] disabled ", key, ": ", tostring(err))
end

--- An empty layout: the safe result of a failed plugin recipe.
function guard.empty()
	return builtin.BoxLayout{}
end

--- Loads a module with pcall; nil (and one log line) if it fails. `path` must be fully qualified
-- ("ui_overhaul_1::/..."): a mod-relative "/..." path only resolves to the owning mod while a module
-- is being loaded; at render time it resolves to the base game (observed in-game).
function guard.module(path)
	local ok, module = pcall(require, path)
	if ok then return module end
	report(path, module)
	return nil
end

--- Calls module[field](...) safely. Returns its result, or `fallback()` (default: an empty layout)
-- if the module or the call fails.
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
function guard.plugin(path, field)
	return function(...) return guard.call(path, field, nil, ...) end
end

return guard
