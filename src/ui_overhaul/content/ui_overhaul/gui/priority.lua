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
--   * Late, after every other mod: for each feature, the recipes it replaces are compared with the
--     other mods' replacements of the same recipes. A mod that comes first wins the whole feature: UI
--     Overhaul's version of that screen stays off. Otherwise the feature's replacements are applied,
--     over a later mod's. A wrapped function that later mods wrapped too is wrapped again, outermost,
--     so UI Overhaul has the last word there; where a mod that comes first wrapped it, the inner link
--     stays, so that mod's wrap is around it and has the last word. Both changes stay in either case.
--   * Mods whose features duplicate one of UI Overhaul's without touching the same function (the same
--     card in the industry window, the same lines in the build tooltip) are listed in OVERLAPS: the one
--     that comes first is shown, the other is held back.
--
-- Where the activation order comes from: generic resource ids are handed out in loading order, the
-- game's own first, then mod by mod in activation order (observed in game), and every resource name
-- starts with its mod id. Which mod a function belongs to: debug.getinfo gives the file it was defined
-- in, and the files of each mod lie under one folder, found from the functions of its replacement
-- configs. Without the debug library (or for a mod this cannot place) UI Overhaul goes first, as it did
-- before this module.
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
---@field generic boolean a widget or framework function many mods wrap for unrelated reasons: no conflict
---@field label string module and field, for the log
---@field first? string a mod that comes first and wrapped it too: its wrap has the last word

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
---@field gates { on: boolean }[] its gated wraps (priority.gated), switched off with a module that failed
---@field winner? string the mod that comes first and changes the same part, when there is one
---@field recipes_done? integer recipes of the modules installed in full so far
---@field chains_done? integer links of the modules installed in full so far
---@field gates_done? integer gated wraps of the modules installed in full so far

---A mod whose feature duplicates one of this mod's without a shared recipe or function.
---@class uo.gui.priority.Overlap
---@field mod string its mod id
---@field feature string this mod's feature
---@field what string what both show, for the log
---@field extension_point? string its plugins there are held back when this mod comes first
---@field hold_back? fun() held back when this mod comes first and the feature installed, called early
--- (after this mod's installs, before the other mod's config runs)
---@field recipe? fun(): function the recipe it replaces with its own version of the feature: its
--- replacement is taken back when this mod comes first

---@alias uo.gui.priority.RecipeSet table<function, true>

---@type uo.gui.priority.Overlap[]
priority.OVERLAPS = {
	{ mod = "cayde_industry_enhanced_1", feature = "industry", what = "industry window cards",
		extension_point = "::IndustryEowExtensionPoint" },
	-- a copy of the station window with its own terminal buttons
	{ mod = "terminal_selector", feature = "station_terminals", what = "station window terminal buttons",
		recipe = function() return require("::/gui/entity_window/station_group/station_group.tl") end },
	{ mod = "gleisbauanzeige_tf3", feature = "build_info", what = "build tooltip measurements",
		-- its config returns at once when this flag is set (tooltip.script.lua, "prepare")
		hold_back = function()
			local construction_react_util = require("::/gui/construction/construction_react_util.tl")
			local fields = construction_react_util --[[@as table<string, any>]]
			fields.__gleisbauanzeigeInstalled = true
		end },
}

local report = guard.reporter("load order: ")

local features = {} ---@type table<string, uo.gui.priority.Feature>
local feature_order = {} ---@type string[]
local current ---@type uo.gui.priority.Feature? the feature whose install is running
local roots = {} ---@type table<string, string> folder ending in "/content/" -> mod id
local positions = {} ---@type table<string, integer> mod id -> its smallest generic resource id
local replaced = {} ---@type table<integer, { mod: string, fn: function }[]> recipe id -> other mods' replacements
local held_back = {} ---@type table<string, true> mod ids whose overlapping plugins are held back
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

--- The mod that called the replacement api: the first file on the stack that belongs to another mod.
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
		feature = { key = key, enabled = enabled, active = enabled, installed = false, recipes = {}, chains = {},
			gates = {} }
		features[key] = feature
		feature_order[#feature_order + 1] = key
	end
	current = feature
	return feature
end

--- Ends the install started by `begin`; `ok` whether it ran without an error. A failed install takes
-- back what it did before the error (its noted replacements, its links, its gated wraps), so a feature
-- of several modules keeps only the modules that installed in full.
---@param ok boolean
function priority.finish(ok)
	local feature = current
	current = nil
	if feature == nil then return end
	if ok then
		feature.installed = true -- a feature of several modules is installed when one of them is
		feature.recipes_done, feature.chains_done = #feature.recipes, #feature.chains
		feature.gates_done = #feature.gates
		return
	end
	for i = #feature.recipes, (feature.recipes_done or 0) + 1, -1 do table.remove(feature.recipes, i) end
	for i = (feature.chains_done or 0) + 1, #feature.chains do feature.chains[i].mode = "off" end
	for i = (feature.gates_done or 0) + 1, #feature.gates do feature.gates[i].on = false end
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
-- `generic`: a function many mods wrap for unrelated reasons (widgets, react.fireEvent): never a
-- conflict, the link stays innermost. Outside an install (specs) the field is wrapped plainly.
---@param module table
---@param field string
---@param make fun(previous: function): function
---@param generic? boolean
function priority.chain(module, field, make, generic)
	local fields = module --[[@as table<string, function?>]]
	local previous = fields[field]
	-- engine functions (react.fireEvent is api.gui.react.fireEvent) need not be Lua functions
	if previous == nil then error(tostring(field) .. " not found") end
	if current == nil then
		fields[field] = make(previous)
		return
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
		label = field, slot = slot }
	fields[field] = chain.slot
	current.chains[#current.chains + 1] = chain
end

--- A make() for builtin_wraps.wrap and the like that keeps the base when the installing feature is
-- not shown, or when the module installing it fails (priority.finish). Outside an install `make`
-- itself.
---@param make fun(base: function): function
---@return fun(base: function): function
function priority.gated(make)
	local feature = current
	if feature == nil then return make end
	local gate = { on = true }
	feature.gates[#feature.gates + 1] = gate
	return function(base)
		local wrapped = make(base)
		return function(...)
			if gate.on and feature.active and feature.installed then return wrapped(...) end
			return base(...)
		end
	end
end

-- The mods whose functions lie between the current value of a chained field and its inner link:
-- they wrapped it after this mod's early config. Searches the upvalues (a wrap keeps the function it
-- wraps in one), at most `limit` functions.
---@param chain uo.gui.priority.Chain
---@return string[] mods
local function wrapped_after(chain)
	local top = (chain.module --[[@as table<string, function>]])[chain.field]
	if top == chain.slot then return {} end
	local limit, seen, parent = 64, {}, {} ---@type integer, table<function, true>, table<function, function>
	local queue, found = { top }, false ---@type function[], boolean
	seen[top] = true
	local i = 1
	while i <= #queue and i <= limit and not found do
		local fn = queue[i]
		for n = 1, 60 do
			local ok, name, value = pcall(debug.getupvalue, fn, n)
			if not ok or name == nil then break end
			if type(value) == "function" and not seen[value] then
				seen[value], parent[value] = true, fn
				if value == chain.slot then found = true break end
				queue[#queue + 1] = value
			end
		end
		i = i + 1
	end
	local mods, listed = {}, {} ---@type string[], table<string, true>
	local fn = found and parent[chain.slot] or top ---@type function?
	while fn ~= nil do
		local mod = priority.owner(fn) or "?"
		if mod ~= "" and mod ~= priority.MOD_ID and not listed[mod] then
			listed[mod] = true
			mods[#mods + 1] = mod
		end
		fn = found and parent[fn] or nil
	end
	return mods
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
			table.insert(replaced[id], { mod = calling_mod(), fn = replacement })
		end)
		return base_replace(recipe, replacement)
	end
	-- held back for now; hold_back() confirms it once this mod's features have installed
	for _i, overlap in ipairs(priority.OVERLAPS) do
		local first = priority.comes_first(overlap.mod)
		if first == false and enabled(overlap.feature) then held_back[overlap.mod] = true end
	end
end

--- After this mod's installs, still before every other mod's config: holds back the overlapping mods
-- (OVERLAPS) whose feature here installed. Where it did not (switched off, or its install failed),
-- that mod is not held back, so its version stays.
function priority.hold_back()
	for _i, overlap in ipairs(priority.OVERLAPS) do
		if held_back[overlap.mod] then
			local feature = features[overlap.feature]
			if feature ~= nil and not feature.installed then
				held_back[overlap.mod] = nil
			else
				if overlap.hold_back then
					local hold_ok, hold_err = pcall(overlap.hold_back)
					if not hold_ok then report(overlap.mod, hold_err) end
				end
				debugPrint("[ui_overhaul] ", overlap.what, ": ui_overhaul_1 comes first in the mod list, ",
					overlap.mod, " is held back")
			end
		end
	end
end

--- The other mods that replaced `recipe`, in the order they did.
---@param recipe function
---@return { mod: string, fn: function }[]
local function replacements_of(recipe)
	local ok, id = pcall(react.GetRecipeId, recipe)
	return ok and id and replaced[id] or {}
end

--- Decides one feature (see the module comment).
---@param feature uo.gui.priority.Feature
local function decide(feature)
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
	local later = {} ---@type string[]
	for _i, part in ipairs(feature.recipes) do
		for _j, other in ipairs(replacements_of(part.recipe)) do
			if priority.comes_first(other.mod) == true then
				feature.winner = feature.winner or other.mod
				report(feature.key, other.mod .. " comes first in the mod list and replaces " .. part.label
					.. "; its version is used")
			else
				later[#later + 1] = other.mod .. " (" .. part.label .. ")"
			end
		end
	end
	if feature.winner then
		feature.active = false
		for _i, chain in ipairs(feature.chains) do chain.mode = "off" end
		debugPrint("[ui_overhaul] ", feature.key, ": off, ", feature.winner, " comes first in the mod list")
		return
	end
	-- its recipes, over the replacements of mods that come later
	for _i, part in ipairs(feature.recipes) do
		local replace = base_replace
		if replace then
			local ok, err = pcall(replace, part.recipe, part.replacement)
			if not ok then report(feature.key, err) end
		end
	end
	-- the replacements of overlapping mods that come later are taken back (OVERLAPS)
	for _i, overlap in ipairs(priority.OVERLAPS) do
		if overlap.feature == feature.key and held_back[overlap.mod] and overlap.recipe then
			local ok, err = pcall(function()
				local recipe = overlap.recipe()
				local id = react.GetRecipeId(recipe)
				local registry = _react
				local current_fn = id and registry.recipeReplace[id]
				if current_fn == nil then return end
				-- back to the replacement before that mod's, if another mod made one (else the base)
				local before ---@type function?
				for _j, other in ipairs(replacements_of(recipe)) do
					if other.fn == current_fn and other.mod == overlap.mod then
						if base_replace then base_replace(recipe, before) end
						return
					end
					before = other.fn
				end
			end)
			if not ok then report(overlap.mod, err) end
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
				fields[chain.field] = function(...)
					if chain.mode == "outer" then return outer(...) end
					return previous(...)
				end
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

--- After every other mod's config: decides each feature.
function priority.late()
	if decided then return end
	decided = true
	for _i, key in ipairs(feature_order) do
		local ok, err = pcall(decide, features[key])
		if not ok then report(key, err) end
	end
end

--- Wraps react.getPlugins so that the plugins of a held-back mod (OVERLAPS) are left out, while this
-- mod's feature that they duplicate is shown (it may still be off: an install that failed, a recipe
-- won by a mod that comes first; then that mod's plugins stay).
function priority.filter_plugins()
	if next(held_back) == nil then return end
	local util = require("::/scripts/util.tl")
	local by_point = {} ---@type table<string, uo.gui.priority.Overlap[]> extension point -> held-back overlaps
	for _i, overlap in ipairs(priority.OVERLAPS) do
		local point = overlap.extension_point
		if held_back[overlap.mod] and point then
			local overlaps = by_point[point] or {}
			overlaps[#overlaps + 1] = overlap
			by_point[point] = overlaps
		end
	end
	if next(by_point) == nil then return end
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
	priority.chain(react, "getPlugins",
	---@param get_plugins fun(extension_point: { id: string }?, ...: any): { recipe: function }[]
	---@return fun(extension_point: { id: string }?, ...: any): { recipe: function }[]
	function(get_plugins)
		---@param extension_point { id: string }?
		---@param ... any passed on unchanged
		---@return { recipe: function }[]
		return function(extension_point, ...)
			local plugins = get_plugins(extension_point, ...)
			local ok, filtered = pcall(function()
				local point = extension_point and extension_point.id
				if point == nil or by_point[point] == nil or type(plugins) ~= "table" then return plugins end
				local drop = {} ---@type uo.gui.priority.RecipeSet[]
				for _i, overlap in ipairs(by_point[point]) do
					if priority.active(overlap.feature) then drop[#drop + 1] = recipes_of(point, overlap.mod) end
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
	end, true)
end

return priority
