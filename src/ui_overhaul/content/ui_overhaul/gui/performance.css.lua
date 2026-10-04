-- Performance card (performance.lua): the slope table spaced like the vehicle window's other
-- tables, a dimmed header row, and a compact load switch beside the headline.
local ssu = require("::/gui/main/stylesheetutil.lua")

---@return table[]
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	add("R::UioVehiclePerformance BoxLayout!uio-performance", { innerSpacing = { 0, 6 } })
	add("R::UioVehiclePerformance TableLayout!uio-performance-table", { gravity = { -1, 0 } })
	add("R::UioVehiclePerformance TableLayout!uio-performance-table TextView", { padding = { 2, 4, 2, 4 } })
	add("R::UioVehiclePerformance TextView!uio-performance-header", { color = colorDefault.NeutralLight })
	add("R::UioVehiclePerformance ToggleButtonGroup!uio-performance-load", { gravity = { 1, 0.5 } })
	add("R::UioVehiclePerformance ToggleButtonGroup!uio-performance-load ToggleButton", { padding = { 2, 6, 2, 6 } })
	return result
end
