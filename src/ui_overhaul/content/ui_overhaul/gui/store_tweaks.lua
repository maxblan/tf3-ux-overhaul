--- Vehicle store (list layout): opens with the newest models first, so the preselected model (the
-- first one) is the newest instead of the oldest, and keeps the player's sort choice for the session.
-- The store's sort state is a local React state created as
--   react.useState({ mode = "YearFrom", ascending = true, groupTypes = true })
-- (line_vehicle_mgmt/vehicle_store_window.tl). The wrapped react.useState recognises exactly that
-- initial value (three keys, these values) and starts from the remembered or the newest-first sort.
-- Any other state is untouched. Installed before the UI starts (store_tweaks.script.lua).
-- The table layout of the store keeps the base sorting.
-- @module ui_overhaul.gui.store_tweaks
local react = require("::/gui/main/react.lua")

local store_tweaks = {}

local remembered = nil -- last sort the player chose: { mode, ascending, groupTypes }
local logged = false

local function is_store_sort(value)
	if type(value) ~= "table" then return false end
	local keys = 0
	for _k in pairs(value) do keys = keys + 1 end
	return keys == 3 and value.mode == "YearFrom" and value.ascending == true and value.groupTypes == true
end

local function copy(t)
	local result = {}
	for k, v in pairs(t) do result[k] = v end
	return result
end

-- A state that records every new sort before passing it on.
local function remembering(state)
	return {
		old = function(_self) return state:old() end,
		set = function(_self, value)
			if type(value) == "table" then remembered = copy(value) end
			return state:set(value)
		end,
		transform = function(_self, fn)
			return state:transform(function(current)
				local value = fn(current)
				if type(value) == "table" then remembered = copy(value) end
				return value
			end)
		end,
		hasExpired = function(_self) return state:hasExpired() end,
	}
end

--- Called from the react-replacement-config before the UI starts.
function store_tweaks.install(_replacement_api)
	local original = react.useState
	react.useState = function(initial, ...)
		if not is_store_sort(initial) then return original(initial, ...) end
		if not logged then
			logged = true
			debugPrint("[ui_overhaul] vehicle store sort: newest first")
		end
		local start = remembered and copy(remembered) or { mode = "YearFrom", ascending = false, groupTypes = true }
		return remembering(original(start, ...))
	end
end

return store_tweaks
