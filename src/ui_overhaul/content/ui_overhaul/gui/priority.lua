--- Which mod wins where UI Overhaul and another mod change the same part of the game's UI: the one
-- that comes first in the mod list's activation order. The game itself has no such rule (observed in
-- game): replacement configs run sorted by their `order` field, and among equal orders in no fixed
-- way, so before this module the winner depended on numbers each author picked.
--
-- How it works. The installer (installer.lua) runs in two react-replacement-configs, one before every
-- other mod's (order -1e9) and one after (order 1e9):
--   * Early: this module learns the activation order and which files belong to which mod, and records
--     which mod replaces which recipe (by wrapping the replacement api the game hands every config).
--     Then each feature installs. Its recipe replacements are only noted; its wraps of module
--     functions go in at once, as the innermost link of the chain (`chain`), switched by this module.
--     After the installs (`ready`) it starts a log of what the other mods' configs write to the loaded
--     modules and to the registry of recipe replacements (`watch`), so that it can tell later who
--     wrapped which function, in which order.
--   * Late, after every other mod, in four steps:
--       1. For each feature, the recipes it replaces are compared with the other mods' replacements of
--          the same recipes. A mod that comes first wins the whole feature: UI Overhaul's version of
--          that screen stays off. So does a feature switched off or whose install failed.
--       2. Mods whose GUI changes duplicate a feature that is shown, without touching the same recipe
--          or function, and that come later in the mod list are held back (OVERLAPS, `hold_back`):
--          their recipe replacements and their wraps of module functions are taken back, their plugins
--          are left out of every extension point. Where such a mod comes first, it wins the feature in
--          step 1.
--       3. The features that are shown apply their replacements, over a later mod's. A wrapped
--          function that later mods wrapped too is wrapped again, outermost, so UI Overhaul has the last
--          word there; where a mod that comes first wrapped it, the inner link stays, so that mod's
--          wrap is around it and has the last word. Both changes stay in either case.
--       4. Every switch is settled (`settle`): a link that runs a feature's wrap is replaced by the
--          wrap itself, a link of a feature that is off by the function it wrapped. From then on no
--          call checks a setting or a decision.
--
-- Where the activation order comes from: generic resource ids are handed out in loading order, the
-- game's own first, then mod by mod in activation order (observed in game), and every resource name
-- starts with its mod id. Which mod a function belongs to: debug.getinfo gives the file it was defined
-- in, and the files of each mod lie under one folder, found from the functions of its replacement
-- configs. Without the debug library (or for a mod this cannot place) UI Overhaul goes first, as it did
-- before this module.
--
-- Chains: the game's debug library has getinfo and traceback only (observed in game), so a chain of
-- wraps cannot be followed through the functions' upvalues. What happened to a field is known from the
-- log `watch` keeps instead: from `ready` until `late`, the function fields of every loaded module (and
-- the registry of recipe replacements) sit behind a metatable that records each write and the mod on
-- the stack that made it. A write can then be taken back where it is the field's last one; a held-back
-- mod's wrap that a third mod wrapped again stays (the log says so). This mod's own links are settled
-- by building the chain anew from below, up to the first link of another mod (`settle`); a link that
-- stays still switches, to the same effect.
--
-- Outside the game (specs) no feature is being installed, and `chain` wraps the field plainly.
-- @module ui_overhaul.gui.priority
local react = require("::/gui/main/react.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")

---@class uo.gui.priority
local priority = {}

priority.MOD_ID = "ui_overhaul_1"

---@alias uo.gui.priority.Mode "inner"|"outer"|"off"

---A function this mod wraps: the inner link (installed early) and, once decided, the outer one.
---@class uo.gui.priority.Chain
---@field module table
---@field field string
---@field make fun(previous: function): function
---@field mode uo.gui.priority.Mode which link runs the feature's wrap; "off": neither
---@field slot function the inner link
---@field inner function make(previous): the feature's wrap at the inner link
---@field previous function the function the inner link wraps
---@field outer_slot? function the outer link, once decided
---@field outer? function make() at the outer link
---@field outer_previous? function the function the outer link wraps
---@field generic boolean a widget or framework function many mods wrap for unrelated reasons: no conflict
---@field label string module and field, for the log
---@field first? string a mod that comes first and wrapped it too: its wrap has the last word
---@field settled? fun(old: function, new: function) told when `settle` puts a wrap `new` (made by `make`)
--- in the place of link `old`

---A recipe a feature replaces.
---@class uo.gui.priority.Recipe
---@field recipe function
---@field replacement function
---@field label string

---@class uo.gui.priority.Feature
---@field key string
---@field enabled boolean the player's setting (settings.lua)
---@field active boolean shown: enabled and not given up to a mod that comes first
---@field installed boolean its install ran without an error
---@field recipes uo.gui.priority.Recipe[]
---@field chains uo.gui.priority.Chain[]
---@field winner? string the mod that comes first and changes the same part, when there is one
---@field recipes_done? integer recipes of the modules installed in full so far
---@field chains_done? integer links of the modules installed in full so far

---A mod whose GUI changes, as a whole, duplicate one of this mod's features without a shared recipe or
-- function. The one that comes first in the mod list is shown; the other is held back (see the module
-- comment). Only mods that change nothing else belong here: all their GUI changes are held back.
---@class uo.gui.priority.Overlap
---@field mod string its mod id
---@field feature string this mod's feature
---@field what string what both show, for the log

---Another mod's replacement of a recipe, as recorded by the replacement api.
---@class uo.gui.priority.Replacement
---@field mod string
---@field recipe function
---@field fn? function

---@alias uo.gui.priority.RecipeSet table<function, true>

---@type uo.gui.priority.Overlap[]
priority.OVERLAPS = {
	-- two plugins in the industry window
	{ mod = "cayde_industry_enhanced_1", feature = "industry", what = "industry window cards" },
	-- a copy of the station window with its own terminal buttons, and a wrap of react.CallOriginalRecipe
	{ mod = "terminal_selector", feature = "station_terminals", what = "station window terminal buttons" },
}

local report = guard.reporter("load order: ")

local features = {} ---@type table<string, uo.gui.priority.Feature>
local feature_order = {} ---@type string[]
-- every chain, in the order it was installed
local all_chains = {} ---@type uo.gui.priority.Chain[]
local current ---@type uo.gui.priority.Feature? the feature whose install is running
local roots = {} ---@type table<string, string> folder ending in "/content/" -> mod id
local positions = {} ---@type table<string, integer> mod id -> its smallest generic resource id
local replaced = {} ---@type table<integer, uo.gui.priority.Replacement[]> recipe id -> other mods' replacements
local candidates = {} ---@type table<string, true> overlapping mods that come later, their feature on
local held_back = {} ---@type table<string, true> mod ids held back (OVERLAPS)
---A table whose function fields `watch` logs: the fields sit in `shadow` meanwhile.
---@class uo.gui.priority.Watched
---@field table table
---@field key string its key in the loader's registry ("" for the recipe registry)
---@field registry boolean the registry of recipe replacements: every write there is a replacement
---@field shadow table<any, any>
---@field writes table<any, uo.gui.priority.Write[]> per field, in order

---A write `watch` logged.
---@class uo.gui.priority.Write
---@field mod string the mod on the stack that made it ("?" where none is known)
---@field value any
---@field previous any what the field held before

local watched = {} ---@type uo.gui.priority.Watched[]
local watched_by_table = {} ---@type table<table, uo.gui.priority.Watched>
-- writes kept per field, in case `late` never runs (another mod's config failing stops the configs)
local WRITE_LIMIT = 32
local base_replace ---@type fun(recipe: function, replacement?: function)? the game's ReplaceRecipe
local decided = false

-- Debug library ----------------------------------------------------------------------------------

--- A source as debug.getinfo gives it, without the leading "@" and with forward slashes; nil if it is
-- not a string.
---@param source any
---@return string?
local function normalized(source)
	if type(source) ~= "string" then return nil end
	return (source:gsub("^@", ""):gsub("\\", "/"))
end

--- The source of a function as debug.getinfo gives it: "<mod id>::/path" for a module loaded with
-- require ("::/path" for the game's own), the file's path on disk for a resource script (observed in
-- game). Nil without the debug library or for a function of the engine.
---@param fn function
---@return string?
local function source_of(fn)
	if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then return nil end
	local ok, info = pcall(debug.getinfo, fn, "S")
	if not ok or type(info) ~= "table" then return nil end
	return normalized(info.source)
end

--- The content folder of a mod on disk, from the source of a file in it and that file's path inside
-- the mod ("/x/y.script" for "<mod>::/x/y.script"): the source without that path, in lower case and
-- ending in "/". Nil if the source does not end in that path (with .lua or .tl).
---@param source string
---@param path string
---@return string?
local function root_of(source, path)
	local lower, inner = source:lower(), path:lower()
	for _i, extension in ipairs({ ".lua", ".tl" }) do
		local tail = inner .. extension
		if #lower > #tail and lower:sub(-#tail) == tail then return lower:sub(1, #lower - #tail) .. "/" end
	end
	return nil
end

--- The mod a source belongs to: a mod id, "" for the game's own files, nil when unknown. A file on
-- disk belongs to the mod whose content folder is the longest start of its path.
---@param source string
---@return string?
local function mod_of(source)
	local mod = source:match("^([^/\\:]*)::/")
	if mod then return mod end
	local lower, found, length = source:lower(), nil, 0 ---@type string, string?, integer
	for root, owner in pairs(roots) do
		if #root > length and lower:sub(1, #root) == root then found, length = owner, #root end
	end
	return found
end

--- The file a function was defined in: "<mod id>::/path" for a module loaded with require ("::/path"
-- for the game's own), the file's path on disk for a resource script; nil when unknown.
---@param fn function
---@return string?
function priority.source(fn)
	return source_of(fn)
end

--- The mod a function belongs to: a mod id, "" for the game's own files, nil when unknown.
---@param fn function
---@return string?
function priority.owner(fn)
	local source = source_of(fn)
	return source and mod_of(source) or nil
end

-- Activation order ------------------------------------------------------------------------------------

--- The resource types whose names tell which mods are active and in which order.
---@return string[]
local function resource_types()
	local types = { "react-replacement-config" }
	local ok = pcall(function()
		for id in pairs(_react.extensionPoints) do types[#types + 1] = "react-plugin " .. id end
	end)
	if not ok then report("extension points", "not readable") end
	return types
end

--- Reads the activation order from the resource ids, and each config's folder from its functions.
local function learn_mods()
	local globals = _G --[[@as table<string, any>]]
	for _i, type_name in ipairs(resource_types()) do
		local ok, ids = pcall(api.res.genericRep.getAllOfType, type_name)
		for _j, id in ipairs(ok and ids or {}) do
			local name_ok, name = pcall(api.res.genericRep.getName, id)
			local mod = name_ok and type(name) == "string" and name:match("^(.-)::") or nil
			if mod and mod ~= "" and (positions[mod] == nil or id < positions[mod]) then positions[mod] = id end
			-- the functions of a replacement config's script (loaded by the game before any config ran)
			if mod and mod ~= "" and type_name == "react-replacement-config" then
				pcall(function()
					local path = tostring(api.res.genericRep.get(id).data.filePath):match("^[^@]+")
					local script = path and globals.game and globals.game[path] ---@type any the game's table of the script
					local inner = path and path:match("::(/.*)$") ---@type string?
					if type(script) ~= "table" or inner == nil then return end
					for _k, value in pairs(script --[[@as table<any, any>]]) do
						local source = type(value) == "function" and source_of(value) or nil
						local root = source and root_of(source, inner)
						if root and roots[root] == nil then roots[root] = mod end
					end
				end)
			end
		end
	end
end

--- Whether `mod` comes before this mod in the activation order; nil if that is not known.
---@param mod string
---@return boolean?
function priority.comes_first(mod)
	local theirs, ours = positions[mod], positions[priority.MOD_ID]
	if theirs == nil or ours == nil then return nil end
	return theirs < ours
end

--- The mod that made the current call (of the replacement api, or a write `watch` logs): the first file
-- on the stack that belongs to another mod.
---@return string
local function calling_mod()
	if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then return "?" end
	for level = 3, 40 do
		local ok, info = pcall(debug.getinfo, level, "S")
		if not ok or type(info) ~= "table" then break end
		local mod = mod_of(normalized(info.source) or "")
		if mod and mod ~= "" and mod ~= priority.MOD_ID then return mod end
	end
	return "?"
end

-- Features ----------------------------------------------------------------------------------------

--- Starts the install of `key`; `enabled` is the player's setting. Returns the feature.
---@param key string
---@param enabled boolean
---@return uo.gui.priority.Feature
function priority.begin(key, enabled)
	local feature = features[key]
	if feature == nil then
		feature = { key = key, enabled = enabled, active = enabled, installed = false, recipes = {}, chains = {} }
		features[key] = feature
		feature_order[#feature_order + 1] = key
	end
	current = feature
	return feature
end

--- Ends the install started by `begin`; `ok` whether it ran without an error. A failed install takes
-- back what it did before the error (its noted replacements, its links), so a feature of several
-- modules keeps only the modules that installed in full.
---@param ok boolean
function priority.finish(ok)
	local feature = current
	current = nil
	if feature == nil then return end
	if ok then
		feature.installed = true -- a feature of several modules is installed when one of them is
		feature.recipes_done, feature.chains_done = #feature.recipes, #feature.chains
		return
	end
	for i = #feature.recipes, (feature.recipes_done or 0) + 1, -1 do table.remove(feature.recipes, i) end
	for i = (feature.chains_done or 0) + 1, #feature.chains do feature.chains[i].mode = "off" end
end

--- Whether feature `key` is shown (enabled, installed and not given up to a mod that comes first).
-- Features never installed through `begin` (specs, the testbench) count as shown.
---@param key string
---@return boolean
function priority.active(key)
	local feature = features[key]
	if feature == nil then return true end
	return feature.active and feature.installed
end

--- Whether `late` has run: from then on `active` does not change.
---@return boolean
function priority.decided()
	return decided
end

--- The mod that comes first and won feature `key`, if one did.
---@param key string
---@return string?
function priority.winner(key)
	local feature = features[key]
	return feature and feature.winner or nil
end

--- Whether feature `key` gives way somewhere to a mod that comes first: it is off for that mod, or
-- such a mod wrapped one of its functions too (and has the last word there).
---@param key string
---@return boolean
function priority.outranked(key)
	local feature = features[key]
	if feature == nil then return false end
	if feature.winner then return true end
	for _i, chain in ipairs(feature.chains) do
		if chain.first then return true end
	end
	return false
end

--- Whether `mod` is held back (OVERLAPS): this mod comes first and the feature it duplicates is shown.
---@param mod string
---@return boolean
function priority.held_back(mod)
	return held_back[mod] == true
end

--- The decisions, for the testbench: one line per feature.
---@return string[]
function priority.describe()
	local lines = {} ---@type string[]
	for _i, key in ipairs(feature_order) do
		local feature = features[key]
		local modes = {} ---@type string[]
		for _j, chain in ipairs(feature.chains) do modes[#modes + 1] = chain.label .. "=" .. chain.mode end
		lines[#lines + 1] = key .. (feature.active and " on" or " off")
			.. (feature.enabled and "" or " (setting)")
			.. (feature.winner and (" (" .. feature.winner .. " first)") or "")
			.. (#modes > 0 and (" " .. table.concat(modes, " ")) or "")
	end
	return lines
end

--- A replacement api for the installing feature: ReplaceRecipe only notes the replacement, which
-- `late` applies unless a mod that comes first replaced the same recipe. Outside an install it is
-- `api` itself.
---@param replacement_api react.ReplacementApi
---@return react.ReplacementApi
function priority.replacement_api(replacement_api)
	if current == nil then return replacement_api end
	local feature = current
	return {
		ReplaceRecipe = function(recipe, replacement)
			feature.recipes[#feature.recipes + 1] = { recipe = recipe, replacement = replacement,
				label = tostring(react.GetRecipeName(recipe)) }
		end,
	}
end

--- Wraps module[field] with make(previous) for the installing feature, as a link the feature can
-- switch: the innermost one now, the outermost one later if no mod that comes first wrapped it too.
-- `late` settles the link: it puts the wrap itself, or with the feature off the function it wrapped,
-- in its place. `generic`: a function many mods wrap for unrelated reasons (widgets,
-- react.fireEvent): never a conflict, the link stays innermost. `settled(old, new)` is told each time a
-- function this put in the chain is replaced. Outside an install (specs) the field is wrapped plainly.
-- Returns the function now in the field.
---@param module table
---@param field string
---@param make fun(previous: function): function
---@param generic? boolean
---@param settled? fun(old: function, new: function)
---@return function
function priority.chain(module, field, make, generic, settled)
	local fields = module --[[@as table<string, function?>]]
	local previous = fields[field]
	-- engine functions (react.fireEvent is api.gui.react.fireEvent) need not be Lua functions
	if previous == nil then error(tostring(field) .. " not found") end
	---@cast previous -nil
	if current == nil then
		local wrapped = make(previous)
		fields[field] = wrapped
		return wrapped
	end
	local inner = make(previous)
	local chain ---@type uo.gui.priority.Chain
	---@param ... any the wrapped function's arguments
	---@return any ... its results
	local function slot(...)
		if chain.mode == "inner" then return inner(...) end
		return previous(...)
	end
	chain = { module = module, field = field, make = make, mode = "inner", generic = generic == true,
		label = field, slot = slot, inner = inner, previous = previous, settled = settled }
	fields[field] = slot
	current.chains[#current.chains + 1] = chain
	all_chains[#all_chains + 1] = chain
	return slot
end

-- The mods that wrote chained field after this mod's early config, in order (from the log `watch`
-- kept; where the module was not watched, the owner of the field's current function).
---@param chain uo.gui.priority.Chain
---@return string[] mods
local function wrapped_after(chain)
	local fields = chain.module --[[@as table<string, function>]]
	local entry = watched_by_table[chain.module]
	local mods, listed = {}, {} ---@type string[], table<string, true>
	---@param mod string
	local function add(mod)
		if mod ~= "" and mod ~= priority.MOD_ID and not held_back[mod] and not listed[mod] then
			listed[mod] = true
			mods[#mods + 1] = mod
		end
	end
	if entry then
		for _i, write in ipairs(entry.writes[chain.field] or {}) do add(write.mod) end
	elseif fields[chain.field] ~= chain.slot then
		add(priority.owner(fields[chain.field]) or "?")
	end
	return mods
end

-- Holding back ---------------------------------------------------------------------------------------

--- The tables whose function fields `watch` logs: the modules loaded with require (the loader's
-- registry, base/init.lua) and the registry of recipe replacements. Not the globals: their table has a
-- metatable of the game's (observed in game). Nor a table with a metatable of its own.
---@return { table: table, key: string, registry: boolean }[]
local function watchable()
	local list, seen = {}, {} ---@type { table: table, key: string, registry: boolean }[], table<table, true>
	---@param t any
	---@param key string
	---@param registry boolean
	local function add(t, key, registry)
		if type(t) == "table" and not seen[t] and getmetatable(t) == nil then
			seen[t] = true
			list[#list + 1] = { table = t, key = key, registry = registry }
		end
	end
	pcall(function()
		for key, module in pairs(_ug_loadedModules) do add(module, key, false) end
	end)
	pcall(function() add(_react.recipeReplace, "", true) end)
	return list
end

--- Starts the log of writes to `t`: its function fields (all fields of the recipe registry) move to a
-- shadow table, and a metatable reads them from there and logs each write (`__pairs` lists both).
---@param t table
---@param key string
---@param registry boolean
local function watch(t, key, registry)
	local fields = t --[[@as table<any, any>]]
	local shadow, writes = {}, {} ---@type table<any, any>, table<any, uo.gui.priority.Write[]>
	local moved = {} ---@type any[]
	-- not the metamethods a module may keep for its objects (vec3.__add): Lua looks those up raw
	for k, v in pairs(fields) do
		if registry or (type(k) == "string" and type(v) == "function" and k:sub(1, 2) ~= "__") then
			moved[#moved + 1] = k
		end
	end
	for _i, k in ipairs(moved) do
		shadow[k] = fields[k]
		fields[k] = nil
	end
	setmetatable(t, {
		__index = shadow,
		__newindex = function(_t, k, v)
			local list = writes[k] or {}
			writes[k] = list
			if #list >= WRITE_LIMIT then table.remove(list, 1) end
			list[#list + 1] = { mod = calling_mod(), value = v, previous = shadow[k] }
			shadow[k] = v
		end,
		__pairs = function(own)
			local all = {} ---@type table<any, any>
			---@diagnostic disable-next-line: no-unknown
			for k, v in next, own do all[k] = v end
			for k, v in next, shadow do all[k] = v end
			return next, all, nil
		end,
	})
	local entry = { table = t, key = key, registry = registry, shadow = shadow, writes = writes }
	watched[#watched + 1] = entry
	watched_by_table[t] = entry
end

-- The loader's registry while `watch` runs: modules loaded meanwhile (by another mod's config) are
-- put here instead, and watched as they arrive.
local loaded_meanwhile ---@type table<string, any>?

--- Watches the modules loaded from now on too: a metatable on the loader's registry (base/init.lua
-- stores each module there once it has run) watches each new module before anyone can wrap it.
local function watch_new_modules()
	local registry = _ug_loadedModules
	if type(registry) ~= "table" or getmetatable(registry) ~= nil then return end
	local added = {} ---@type table<string, any>
	loaded_meanwhile = added
	setmetatable(registry, {
		__index = added,
		__newindex = function(_t, key, module)
			added[key] = module
			if type(module) == "table" and getmetatable(module) == nil and watched_by_table[module] == nil then
				local ok, err = pcall(watch, module, tostring(key), false)
				if not ok then report("watch " .. tostring(key), err) end
			end
		end,
		__pairs = function(own)
			local all = {} ---@type table<any, any>
			---@diagnostic disable-next-line: no-unknown
			for k, v in next, own do all[k] = v end
			for k, v in next, added do all[k] = v end
			return next, all, nil
		end,
	})
end

--- Ends every log: each table gets its fields back, plain.
local function unwatch()
	if loaded_meanwhile then
		setmetatable(_ug_loadedModules, nil)
		for key, module in pairs(loaded_meanwhile) do _ug_loadedModules[key] = module end
		loaded_meanwhile = nil
	end
	for _i, entry in ipairs(watched) do
		setmetatable(entry.table, nil)
		local fields = entry.table --[[@as table<any, any>]]
		for k, v in pairs(entry.shadow) do fields[k] = v end
	end
end

--- After this mod's installs, still before every other mod's config: starts the log of what the
-- other mods' configs write (see the module comment). Needs debug.getinfo, to know who writes.
function priority.ready()
	if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then return end
	for _i, entry in ipairs(watchable()) do
		local ok, err = pcall(watch, entry.table, entry.key, entry.registry)
		if not ok then report("watch " .. entry.key, err) end
	end
	local ok, err = pcall(watch_new_modules)
	if not ok then report("watch new modules", err) end
end

--- Takes back `mod`'s writes at the end of each field's log: the field gets what the last other write
-- left there, or what it held before. In a module only the replacement of a field (its wrap of a
-- function) counts, not a field it added; in the recipe registry every write is a replacement. A
-- write of `mod` under another mod's later write stays. Returns how many fields it took back and how
-- many writes stay.
---@param mod string
---@return integer taken
---@return integer kept
local function take_back(mod)
	local taken, kept = 0, 0
	for _i, entry in ipairs(watched) do
		-- its own modules hold its own functions, not wraps
		if entry.key:sub(1, #mod + 2) ~= mod .. "::" then
			local fields = entry.table --[[@as table<any, any>]]
			for key, list in pairs(entry.writes) do
				---@param write uo.gui.priority.Write
				---@return boolean
				local function counts(write)
					return write.mod == mod and (entry.registry or write.previous ~= nil)
				end
				local n = #list
				while n >= 1 and (counts(list[n]) or (held_back[list[n].mod] and list[n].mod ~= mod)) do n = n - 1 end
				if n < #list and counts(list[#list]) then
					fields[key] = n >= 1 and list[n].value or list[1].previous
					taken = taken + 1
				end
				for i = 1, n do
					if counts(list[i]) then kept = kept + 1 end
				end
			end
		end
	end
	return taken, kept
end

--- The other mods that replaced `recipe`, in the order they did.
---@param recipe function
---@return uo.gui.priority.Replacement[]
local function replacements_of(recipe)
	local ok, id = pcall(react.GetRecipeId, recipe)
	return ok and id and replaced[id] or {}
end

--- Holds back `overlap.mod`: its recipe replacements and its wraps of module functions are taken
-- back (`take_back`; the replacement or the function before it is used again), and from now on its
-- plugins are left out of every extension point (`filter_plugins`).
---@param overlap uo.gui.priority.Overlap
local function hold_back(overlap)
	local mod = overlap.mod
	held_back[mod] = true
	local taken, kept = take_back(mod)
	debugPrint("[ui_overhaul] ", overlap.what, ": ui_overhaul_1 comes first in the mod list, ", mod,
		" is held back (", taken, " replacements and wraps taken back",
		kept > 0 and (", " .. kept .. " stay under another mod's") or "", ", its plugins left out)")
	if kept > 0 then report(mod, kept .. " of its replacements or wraps stay under another mod's") end
end

--- Wraps react.getPlugins so that the plugins of the held-back mods are left out, at every extension
-- point. Installed by `late` when a mod is held back.
local function filter_plugins()
	local util = require("::/scripts/util.tl")
	local mods = {} ---@type string[]
	for _i, overlap in ipairs(priority.OVERLAPS) do
		if held_back[overlap.mod] then mods[#mods + 1] = overlap.mod end
	end
	---@type table<string, uo.gui.priority.RecipeSet> extension point and mod id -> its plugin recipes there
	local recipes = {}
	---@param point string
	---@param mod string
	---@return uo.gui.priority.RecipeSet
	local function recipes_of(point, mod)
		local key = point .. "\0" .. mod
		if recipes[key] then return recipes[key] end
		local set = {} ---@type table<function, true>
		for _i, id in ipairs(api.res.genericRep.getAllOfType("react-plugin " .. point)) do
			if api.res.genericRep.getName(id):sub(1, #mod + 2) == mod .. "::" then
				local recipe = util.useFn(api.res.genericRep.get(id).data.filePath)
				if recipe then set[recipe] = true end
			end
		end
		recipes[key] = set
		return set
	end
	local fields = react --[[@as table<string, function>]]
	---@type fun(extension_point: { id: string }?, ...: any): { recipe: function }[]
	local get_plugins = fields.getPlugins
	---@param extension_point { id: string }?
	---@param ... any passed on unchanged
	---@return { recipe: function }[]
	fields.getPlugins = function(extension_point, ...)
		local plugins = get_plugins(extension_point, ...)
		local ok, filtered = pcall(function()
			local point = extension_point and extension_point.id
			if point == nil or type(plugins) ~= "table" then return plugins end
			local drop = {} ---@type uo.gui.priority.RecipeSet[]
			for _i, mod in ipairs(mods) do
				local set = recipes_of(point, mod)
				if next(set) ~= nil then drop[#drop + 1] = set end
			end
			if #drop == 0 then return plugins end
			local kept = {} ---@type { recipe: function }[]
			for _i, plugin in ipairs(plugins) do
				local dropped = false
				for _j, set in ipairs(drop) do dropped = dropped or set[plugin.recipe] == true end
				if not dropped then kept[#kept + 1] = plugin end
			end
			return kept
		end)
		if ok then return filtered end
		report("plugins", filtered)
		return plugins
	end
end

-- Steps ---------------------------------------------------------------------------------------------

--- Before every other mod's config: learns the mods and starts recording their replacements.
---@param replacement_api react.ReplacementApi
---@param enabled fun(feature: string): boolean the player's settings
function priority.early(replacement_api, enabled)
	local ok, err = pcall(learn_mods)
	if not ok then report("mods", err) end
	base_replace = replacement_api.ReplaceRecipe
	local api_fields = replacement_api --[[@as table<string, function>]]
	api_fields.ReplaceRecipe = function(recipe, replacement)
		pcall(function()
			local id = react.GetRecipeId(recipe)
			if id == nil then return end
			replaced[id] = replaced[id] or {}
			table.insert(replaced[id], { mod = calling_mod(), recipe = recipe, fn = replacement })
		end)
		return base_replace(recipe, replacement)
	end
	-- the overlapping mods that may be held back; `late` decides
	for _i, overlap in ipairs(priority.OVERLAPS) do
		if priority.comes_first(overlap.mod) == false and enabled(overlap.feature) then
			candidates[overlap.mod] = true
		end
	end
end

--- Step 1: whether the feature is shown (see the module comment).
---@param feature uo.gui.priority.Feature
local function choose(feature)
	if not (feature.enabled and feature.installed) then
		feature.active = false
		for _i, chain in ipairs(feature.chains) do chain.mode = "off" end
		return
	end
	-- a mod that comes first and duplicates the feature (OVERLAPS)
	for _i, overlap in ipairs(priority.OVERLAPS) do
		if overlap.feature == feature.key and priority.comes_first(overlap.mod) == true then
			feature.winner = overlap.mod
		end
	end
	-- a mod that comes first and replaces one of its recipes
	for _i, part in ipairs(feature.recipes) do
		for _j, other in ipairs(replacements_of(part.recipe)) do
			if priority.comes_first(other.mod) == true then
				feature.winner = feature.winner or other.mod
				report(feature.key, other.mod .. " comes first in the mod list and replaces " .. part.label
					.. "; its version is used")
			end
		end
	end
	if feature.winner then
		feature.active = false
		for _i, chain in ipairs(feature.chains) do chain.mode = "off" end
		debugPrint("[ui_overhaul] ", feature.key, ": off, ", feature.winner, " comes first in the mod list")
	end
end

--- Step 3: the replacements and wraps of a feature that is shown (see the module comment).
---@param feature uo.gui.priority.Feature
local function apply(feature)
	if not priority.active(feature.key) then return end
	-- its recipes, over the replacements of mods that come later
	local later = {} ---@type string[]
	for _i, part in ipairs(feature.recipes) do
		for _j, other in ipairs(replacements_of(part.recipe)) do
			if not held_back[other.mod] then later[#later + 1] = other.mod .. " (" .. part.label .. ")" end
		end
		local replace = base_replace
		if replace then
			local ok, err = pcall(replace, part.recipe, part.replacement)
			if not ok then report(feature.key, err) end
		end
	end
	if #later > 0 then
		debugPrint("[ui_overhaul] ", feature.key, ": used, it comes first in the mod list before ",
			table.concat(later, ", "))
	end
	-- its wraps: outermost unless a mod that comes first wrapped the same function after it
	for _i, chain in ipairs(feature.chains) do
		-- (a link of a module whose install failed stays off)
		if not chain.generic and chain.mode ~= "off" and type(debug) == "table" then
			local mods = wrapped_after(chain)
			local any_first, any_later = false, false
			for _j, mod in ipairs(mods) do
				if priority.comes_first(mod) == true then
					any_first = true
					chain.first = chain.first or mod
				else
					any_later = true
				end
			end
			if any_later and not any_first then
				local fields = chain.module --[[@as table<string, function>]]
				local previous = fields[chain.field]
				local outer = chain.make(previous)
				---@param ... any the wrapped function's arguments
				---@return any ... its results
				local function outer_slot(...)
					if chain.mode == "outer" then return outer(...) end
					return previous(...)
				end
				chain.outer_slot, chain.outer, chain.outer_previous = outer_slot, outer, previous
				fields[chain.field] = outer_slot
				chain.mode = "outer"
			end
			if #mods > 0 then
				-- with mods on both sides in the mod list, this link stays inside: the one that comes first
				-- has the last word over UI Overhaul, a later one may still wrap outside it (as it would
				-- without this mod); only taking its wrap apart could change that
				debugPrint("[ui_overhaul] ", feature.key, ": ", chain.label, " also wrapped by ",
					table.concat(mods, ", "), any_first and " (one comes first: its wrap has the last word"
						.. (any_later and "; one that comes later also wraps it outside this mod's)" or ")")
						or " (ui_overhaul_1 comes first: its wrap has the last word)")
			end
		end
	end
end

--- Step 4: each chained field built anew from below, from the first link of another mod (or the
-- function at the bottom) up to the top: a link of a feature that runs its wrap becomes the wrap, made
-- again over what is now below it where that changed; a link that runs nothing becomes what is below
-- it. Only where the top link is this mod's (a link under another mod's cannot be taken out). Returns
-- the labels of the links that stay: those still switch, to the same effect.
---@return string[]
local function settle()
	---@type table<function, { chain: uo.gui.priority.Chain, outer: boolean }>
	local slots = {}
	local fields = {} ---@type { module: table, field: string }[]
	---@type table<table, table<string, true> >
	local listed = {}
	for _i, chain in ipairs(all_chains) do
		slots[chain.slot] = { chain = chain, outer = false }
		local outer_slot = chain.outer_slot
		if outer_slot then slots[outer_slot] = { chain = chain, outer = true } end
		listed[chain.module] = listed[chain.module] or {}
		if not listed[chain.module][chain.field] then
			listed[chain.module][chain.field] = true
			fields[#fields + 1] = { module = chain.module, field = chain.field }
		end
	end
	local gone = {} ---@type table<function, true>
	---@param fn function
	---@return function
	local function final(fn)
		local link = slots[fn]
		if link == nil then return fn end
		gone[fn] = true
		local chain = link.chain
		local old_below = (link.outer and chain.outer_previous or chain.previous) --[[@as function]]
		local wrap = (link.outer and chain.outer or chain.inner) --[[@as function]]
		local below = final(old_below)
		if chain.mode ~= (link.outer and "outer" or "inner") then return below end
		local new = below == old_below and wrap or chain.make(below)
		if chain.settled then chain.settled(fn, new) end
		return new
	end
	for _i, entry in ipairs(fields) do
		local module = entry.module --[[@as table<string, function>]]
		if slots[module[entry.field]] then
			local ok, result = pcall(final, module[entry.field])
			if ok then module[entry.field] = result else report(entry.field, result) end
		end
	end
	local stayed = {} ---@type string[]
	for fn, link in pairs(slots) do
		if not gone[fn] then stayed[#stayed + 1] = link.chain.label .. (link.outer and " (outer)" or "") end
	end
	table.sort(stayed)
	return stayed
end

--- After every other mod's config: decides each feature, holds back the overlapping mods, applies
-- the features that are shown and settles every switch (see the module comment).
function priority.late()
	if decided then return end
	decided = true
	local unwatched, unwatch_err = pcall(unwatch)
	if not unwatched then report("unwatch", unwatch_err) end
	for _i, key in ipairs(feature_order) do
		local ok, err = pcall(choose, features[key])
		if not ok then report(key, err) end
	end
	for _i, overlap in ipairs(priority.OVERLAPS) do
		if candidates[overlap.mod] and not held_back[overlap.mod] and priority.active(overlap.feature) then
			local ok, err = pcall(hold_back, overlap)
			if not ok then report(overlap.mod, err) end
		end
	end
	if next(held_back) ~= nil then
		local ok, err = pcall(filter_plugins)
		if not ok then report("plugin filter", err) end
	end
	for _i, key in ipairs(feature_order) do
		local ok, err = pcall(apply, features[key])
		if not ok then report(key, err) end
	end
	local ok, stayed = pcall(settle)
	if not ok then
		report("settle", stayed)
	elseif #stayed > 0 then
		debugPrint("[ui_overhaul] load order: switched links that stay under another mod's (they keep switching): ",
			table.concat(stayed, ", "))
	end
	watched, watched_by_table = {}, {}
end

return priority
