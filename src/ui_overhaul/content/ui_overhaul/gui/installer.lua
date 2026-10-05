--- Installs the mod's features, in two react-replacement-configs (installer.script.lua):
--   * installer_early.res.lua (order -1e9), before every other mod's config: priority.lua learns the
--     mods and their activation order, then each feature the player left on installs (its wraps go in
--     as the innermost link, its recipe replacements are only noted);
--   * installer_late.res.lua (order 1e9), after every other mod's config: priority.lua decides, feature
--     by feature, which mod wins where both change the same part (the one that comes first in the mod
--     list), and applies the result.
-- Each feature's install runs in pcall: one that fails leaves that part of the game vanilla and logs
-- one line; the others are not affected.
-- @module ui_overhaul.gui.installer
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")
local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")
local settings = require("ui_overhaul_1::/ui_overhaul/gui/settings.lua")

---@class uo.gui.installer
local installer = {}

local GUI = "ui_overhaul_1::/ui_overhaul/gui/"

---@class uo.gui.installer.Install
---@field feature string settings.FEATURES key
---@field module string file in gui/, without ".lua"
---@field fn? string the module's function, default "install"
---@field label string for the log

-- In this order; the Line Manager tweaks last (they used to have a higher order than the rest).
---@type uo.gui.installer.Install[]
installer.INSTALLS = {
	{ feature = "catchment", module = "catchment", label = "catchment overlay" },
	{ feature = "construction", module = "construction", label = "construction menu patch" },
	{ feature = "build_info", module = "construction", fn = "install_build_info", label = "build tooltip measurements" },
	{ feature = "earnings", module = "earnings", label = "earnings tooltip" },
	{ feature = "finances", module = "finances", label = "finance statements" },
	{ feature = "industry", module = "industry_cards", label = "industry blocked-area switch" },
	{ feature = "line_window", module = "line_vehicles", label = "line window vehicles card" },
	{ feature = "line_manager", module = "lvm_rows", label = "Line Manager rows" },
	{ feature = "minimize", module = "minimize", label = "window minimize" },
	{ feature = "notifications", module = "notifications", label = "notification ridge" },
	{ feature = "performance", module = "performance", label = "performance tooltip" },
	{ feature = "sliders", module = "sliders", label = "slider wheel and typing" },
	{ feature = "station_terminals", module = "station_terminals", label = "station terminal buttons" },
	{ feature = "statistics", module = "statistics_lines", label = "statistics lines tab" },
	{ feature = "statistics", module = "statistics_stations", label = "statistics stations tab" },
	{ feature = "statistics", module = "statistics_vehicles", label = "statistics vehicles tab" },
	{ feature = "statistics", module = "statistics_warehouses", label = "statistics warehouses tab" },
	{ feature = "vehicle_store", module = "store_tweaks", label = "vehicle store sort" },
	{ feature = "subsidies", module = "subsidies", label = "subsidy texts" },
	{ feature = "terminals", module = "terminals", label = "terminal usage buttons" },
	{ feature = "windows", module = "tool_stack", label = "tool stack" },
	{ feature = "vehicle_tooltip", module = "vehicle_tooltip", label = "vehicle tooltip" },
	{ feature = "entity_windows", module = "window_tweaks", label = "entity window tweaks" },
	{ feature = "line_manager", module = "lvm_tweaks", label = "Line Manager tweaks" },
}

local early_done, late_done = false, false

--- Before every other mod's replacement config.
---@param replacement_api react.ReplacementApi
function installer.early(replacement_api)
	if early_done then return end
	early_done = true
	debugPrint("[ui_overhaul] settings: ", settings.describe())
	priority.early(replacement_api, settings.enabled)
	for _i, install in ipairs(installer.INSTALLS) do
		local enabled = settings.enabled(install.feature)
		priority.begin(install.feature, enabled)
		local ok = false
		if enabled then
			local module = guard.module(GUI .. install.module .. ".lua")
			local fn = module and module[install.fn or "install"]
			if type(fn) == "function" then
				local err ---@type any what pcall caught
				ok, err = pcall(fn, priority.replacement_api(replacement_api))
				if not ok then debugPrint("[ui_overhaul] ", install.label, " not installed: ", tostring(err)) end
			elseif module then
				debugPrint("[ui_overhaul] ", install.label, " not installed: no ", install.fn or "install")
			end
		end
		priority.finish(ok)
	end
	local ok, err = pcall(priority.filter_plugins)
	if not ok then debugPrint("[ui_overhaul] plugin filter not installed: ", tostring(err)) end
end

--- After every other mod's replacement config.
---@param _replacement_api react.ReplacementApi
function installer.late(_replacement_api)
	if late_done then return end
	late_done = true
	priority.late()
end

return installer
