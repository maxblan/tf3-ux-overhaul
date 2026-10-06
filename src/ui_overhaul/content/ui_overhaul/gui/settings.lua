--- The player's settings: each feature of the mod can be switched off in the mod's settings (the gear
-- next to the mod in the game's mod list, also when loading a savegame). Read once, before the UI
-- starts; a feature switched off is not installed, so that part of the game stays vanilla and other
-- mods that change it work as without this mod.
--
-- The keys and the order are those of the params in mod.json (spec/gui/settings_spec.lua checks that
-- both agree). The game hands each param over as the 1-based index of the chosen value: 1 = On, 2 = Off.
-- @module ui_overhaul.gui.settings

---@class uo.gui.settings
local settings = {}

settings.MOD_ID = "ui_overhaul_1"

-- Feature keys, in the order of mod.json's params (each param's key is "uio_" .. key).
settings.FEATURES = {
	"line_manager", -- Line Manager: line and vehicle rows, model row, confirmations, add-stop hint
	"terminals", -- Select Terminals popover: three buttons per terminal, greyed terminals
	"station_terminals", -- Station window: Select Terminals button per line stop
	"line_window", -- Line window: Add/Remove Vehicle, vehicle rows, Stops card
	"vehicle_tooltip", -- Vehicle hover on the map
	"performance", -- Vehicle window: Performance card with the game's rating
	"statistics", -- Statistics: quick filters, totals, sorting, warehouse cargo
	"finances", -- Finances: income statement
	"windows", -- Windows side by side, kept open on map clicks
	"minimize", -- Minimize button in title bars
	"sections", -- Entity windows: sections stay open, several at once
	"sell_confirm", -- Vehicle window: Sell needs a second click
	"town_growth", -- Town window: what limits growth, progress as text
	"promotion_pending", -- Locked perk: promotion pending
	"industry", -- Industry window: Development and Served by cards, blocked area switch
	"construction", -- Construction menus: merged tabs, track order, Configure tab
	"bulldozer_warning", -- Bulldozer tooltip: stations that lines stop at
	"sliders", -- Mouse wheel on construction sliders, typed values on sliders
	"notifications", -- Notification groups and colours
	"catchment", -- Catchment area buttons
	"subsidies", -- Subsidy states, rings and texts
	"earnings", -- Earnings tooltip with the last 30 days
	"vehicle_store", -- Vehicle store: newest first
}

local known = {} ---@type table<string, true>
for _i, key in ipairs(settings.FEATURES) do known[key] = true end

---@type table<string, number>?
local values

--- The mod's param values by param key, from the game (an empty table where it has none).
---@return table<string, number>
local function read()
	if values then return values end
	local ok, all = pcall(function() return api.engine.config.getModParams() end)
	local own = ok and type(all) == "table" and all[settings.MOD_ID] or nil
	values = type(own) == "table" and own or {}
	return values
end

--- Whether the player left feature `key` switched on (the default, also for a key without a param).
---@param key string
---@return boolean
function settings.enabled(key)
	if not known[key] then return true end
	local ok, value = pcall(function() return read()["uio_" .. key] end)
	return not (ok and value == 2)
end

--- The settings as one line for the log: the features switched off, or "all on".
---@return string
function settings.describe()
	local off = {} ---@type string[]
	for _i, key in ipairs(settings.FEATURES) do
		if not settings.enabled(key) then off[#off + 1] = key end
	end
	return #off == 0 and "all features on" or ("switched off: " .. table.concat(off, ", "))
end

--- For the specs: forget the values read.
function settings.reset()
	values = nil
end

return settings
