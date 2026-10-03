-- Statistics "Lines" tab: the line with quick filters and totals above the table.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::LinesStatistic BoxLayout!uxo-statistics-quick-filters", {
		innerSpacing = { 12, 0 },
		margin = { 4, 18, 6, 18 },
	})
	return result
end
