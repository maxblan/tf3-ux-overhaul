--- Vehicle store (list layout): opens with the newest models first, so the preselected model (the
-- first one) is the newest instead of the oldest, and keeps the player's sort choice for the session.
-- The store's sort state is a local React state created as
--   react.useState({ mode = "YearFrom", ascending = true, groupTypes = true })
-- (line_vehicle_mgmt/vehicle_store_window.tl). The wrapped react.useState recognises exactly that
-- initial value (three keys, these values) and starts from the remembered or the newest-first sort.
-- Any other state is untouched. Installed before the UI starts (installer.lua).
-- The table layout of the store keeps the base sorting.
-- @module ui_overhaul.gui.store_tweaks
local react = require("::/gui/main/react.lua")
local table_util = require("::/scripts/table_util.tl")
local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")

local store_tweaks = {}

---@alias uo.gui.store_tweaks.Sort game.gui.line_vehicle_mgmt.vehicle_store.VehicleBrowserSort

---@type uo.gui.store_tweaks.Sort?
local remembered = nil -- last sort the player chose: { mode, ascending, groupTypes }
local logged = false

---@param value any any hook's initial value
---@return boolean
local function is_store_sort(value)
	if type(value) ~= "table" then return false end
	local keys = 0
	for _k in pairs(value --[[@as table<any, any>]]) do keys = keys + 1 end -- a table, checked above
	return keys == 3 and value.mode == "YearFrom" and value.ascending == true and value.groupTypes == true
end

local copy = table_util.shallowCopy

-- A state that records every new sort before passing it on.
---@param state react.State<uo.gui.store_tweaks.Sort>
---@return react.State<uo.gui.store_tweaks.Sort>
local function remembering(state)
	---@type react.State<uo.gui.store_tweaks.Sort>
	local wrapped = {
		old = function(_self) return state:old() end,
		set = function(_self, value)
			if type(value) == "table" then remembered = copy(value) end
			return state:set(value)
		end,
		transform = function(_self, fn)
			---@param current uo.gui.store_tweaks.Sort
			---@return uo.gui.store_tweaks.Sort
			local function remember(current)
				local value = fn(current) ---@type uo.gui.store_tweaks.Sort
				if type(value) == "table" then remembered = copy(value) end
				return value
			end
			return state:transform(remember)
		end,
		hasExpired = function(_self) return state:hasExpired() end,
	}
	return wrapped
end

--- Called by installer.lua before the UI starts.
---@param _replacement_api react.ReplacementApi
function store_tweaks.install(_replacement_api)
	-- the previous useState in the chain (the game's, or another mod's wrapper around it); generic:
	-- every recipe uses it, this mod changes one state only
	priority.chain(react, "useState",
	---@param original fun(...: any): any
	---@return fun(...: any): any
	function(original)
		---@param initial any any hook's initial value
		---@param ... any passed on unchanged to the previous function
		---@return any ... whatever the previous function returns
		return function(initial, ...)
			if not is_store_sort(initial) then return original(initial, ...) end
			if not logged then
				logged = true
				debugPrint("[ui_overhaul] vehicle store sort: newest first")
			end
			local start = remembered and copy(remembered) or { mode = "YearFrom", ascending = false, groupTypes = true }
			return remembering(original(start, ...))
		end
	end, true)
end

return store_tweaks
