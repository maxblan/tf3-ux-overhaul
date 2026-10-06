--- Whether the game still has what a feature takes from it. The mod builds on the base game's modules
-- (their recipes and functions), which are no public API: a game update may rename or remove one.
-- Before a feature installs, the installer asks here whether every field its modules read from a base
-- module is still there (gui/needs.lua, generated from the code by tools/needs.py). If one is missing,
-- the feature is left vanilla and the log names what is missing, instead of the feature failing when
-- a window renders. Recipes that change their content without changing their names are out of reach
-- of this check; for those the render-time guards remain (guard.base, fallback.lua).
-- @module ui_overhaul.gui.compat

---@class uo.gui.compat
local compat = {}

---@type uo.gui.needs?
local needs

---@return uo.gui.needs
local function table_of_needs()
	if needs == nil then
		local ok, loaded = pcall(require, "ui_overhaul_1::/ui_overhaul/gui/needs.lua")
		needs = ok and type(loaded) == "table" and loaded or { modules = {}, requires = {}, plugins = {} }
	end
	return needs
end

--- For the specs: use `t` instead of gui/needs.lua.
---@param t uo.gui.needs?
function compat.use(t)
	needs = t
end

local loaded = {} ---@type table<string, table|false> base path -> the module, false if it does not load

---@param path string
---@return table|false
local function base_module(path)
	if loaded[path] == nil then
		local ok, module = pcall(require, path)
		loaded[path] = ok and type(module) == "table" and module or false
	end
	return loaded[path]
end

--- The game's build, as it names it, or nil.
---@return string?
function compat.build()
	local ok, build = pcall(function() return getBuildVersion() end)
	return ok and build ~= nil and tostring(build) or nil
end

--- What the GUI module `module` (a file in gui/, without ".lua") and the modules it requires read from
-- the base game and the game no longer has, as "path field" texts, together with what the plugins of
-- `feature` render. Empty when everything is there.
---@param module string
---@param feature? string
---@return string[]
function compat.missing(module, feature)
	local t = table_of_needs()
	local result, seen = {}, {} ---@type string[], table<string, true>
	---@param name string
	local function visit(name)
		if seen[name] then return end
		seen[name] = true
		local fields = t.modules[name] or {}
		local paths = {} ---@type string[]
		for path in pairs(fields) do paths[#paths + 1] = path end
		table.sort(paths)
		for _i, path in ipairs(paths) do
			local base = base_module(path)
			for _j, field in ipairs(fields[path]) do
				local present = false
				if base then
					-- a base module's field is any Lua value: only whether it is there counts
					---@return boolean
					local function has() return base[field] ~= nil end
					local ok, there = pcall(has)
					present = ok and there
				end
				if not present then result[#result + 1] = path .. " " .. field end
			end
		end
		for _i, required in ipairs(t.requires[name] or {}) do visit(required) end
	end
	visit(module)
	for _i, plugin in ipairs(feature and t.plugins[feature] or {}) do visit(plugin) end
	return result
end

return compat
