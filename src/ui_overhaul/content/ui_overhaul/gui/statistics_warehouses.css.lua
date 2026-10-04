-- Statistics, Warehouses tab (statistics_warehouses.lua): a quantity after each cargo icon in the
-- Stocks column, and the cargo picker's icons at the size of the vanilla cargo icons.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::WarehouseCargoTypesCell TextView!uio-warehouse-count", { margin = { 0, 8, 0, 2 }, gravity = { 0, 0.5 } })
	add("ToggleButtonGroup!uio-warehouse-cargo-picker ImageView!uio-warehouse-cargo-pick",
		{ size = { 18, 18 }, gravity = { 0.5, 0.5 } })
	add("BoxLayout!uio-statistics-quick-filters ToggleButtonGroup!uio-warehouse-cargo-picker", { margin = { 0, 0, 4, 0 } })
	return result
end
