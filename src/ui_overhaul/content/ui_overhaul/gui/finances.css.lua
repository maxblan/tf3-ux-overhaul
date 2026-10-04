-- Finance window (finances.lua): totals of the statements in the medium weight the game uses for
-- headlines, and the view buttons spaced like the window's other button rows.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::FinancesTable TextView!uio-statement-total", { fontWeight = "Medium" })
	add("R::FinancesTable ToggleButtonGroup!uio-finances-views", { margin = { 0, 0, 8, 0 }, gravity = { 0, 0 } })
	return result
end
