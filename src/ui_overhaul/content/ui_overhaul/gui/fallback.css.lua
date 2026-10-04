-- Replacements with a fallback (fallback.lua): the parent wraps the shown recipe (the mod's child or
-- the base) in a BoxLayout of class uio-fallback, which must not change the layout. Some base rules
-- select every BoxLayout under the replaced recipe (game_bar_display_earnings.css.lua:
-- R::GameBarEarningsPlugin BoxLayout, outerSpacing 14; finances.css.lua: R::FinancesTable > BoxLayout;
-- notifications.css.lua: R::NotificationPopups > BoxLayout), so the wrapper gets the same selectors
-- with its class added, which are more specific. The wrapper and the shown recipe fill the replaced
-- node, which the base stylesheet sizes as it sized the base root.
local ssu = require("::/gui/main/stylesheetutil.lua")

-- recipe names of the replacements; the tool stack names its node "ToolStack" without R:: (builtin.lua)
local RECIPES = { "GameBarEarningsPlugin", "FinancesTable", "NotificationPopups", "LinesStatistic",
	"StationsStatistic", "VehiclesStatistic", "WarehousesStatistic", "TerminalSelection" }
local NAMED = { "ToolStack" }

local NEUTRAL = { innerSpacing = { 0, 0 }, outerSpacing = { 0, 0 }, gravity = { -1, -1 } }
local FILL = { gravity = { -1, -1 } }

---@return table[]
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("BoxLayout!uio-fallback", NEUTRAL)
	---@type string[]
	local selectors = {}
	for _i, name in ipairs(RECIPES) do selectors[#selectors + 1] = "R::" .. name end
	for _i, name in ipairs(NAMED) do selectors[#selectors + 1] = name end
	for _i, node in ipairs(selectors) do
		add(node .. " BoxLayout!uio-fallback", NEUTRAL)
		add(node .. " > BoxLayout!uio-fallback", NEUTRAL)
		add("BoxLayout!uio-fallback > " .. node, FILL)
	end
	return result
end
