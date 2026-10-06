-- Performance card (performance.lua): the rating spaced like the vehicle window's other cards.
local ssu = require("::/gui/main/stylesheetutil.lua")

---@return table[]
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UioVehiclePerformance BoxLayout!uio-performance", { innerSpacing = { 0, 6 } })
	return result
end
