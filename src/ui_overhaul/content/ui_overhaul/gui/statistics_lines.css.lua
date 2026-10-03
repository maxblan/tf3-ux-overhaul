-- Statistics "Lines", "Vehicles" and "Stations" tabs: the line with quick filters and totals above the table.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	for _i, recipe in ipairs({ "LinesStatistic", "VehiclesStatistic", "StationsStatistic" }) do
		add("R::" .. recipe .. " BoxLayout!uio-statistics-quick-filters", {
			innerSpacing = { 12, 0 },
			margin = { 4, 18, 6, 18 },
		})
	end
	return result
end
