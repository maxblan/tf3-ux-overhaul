-- Statistics, Warehouses tab (statistics_warehouses.lua): a quantity after each cargo icon in the
-- Stocks column, and the cargo picker's icons at the size of the vanilla cargo icons.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::WarehouseCargoTypesCell TextView!uio-warehouse-count", { margin = { 0, 8, 0, 2 }, gravity = { 0, 0.5 } })
	-- the cargo drop-down next to the quick filters
	add("ComboBox!uio-warehouse-cargo-picker", { margin = { 0, 0, 0, 12 }, minSize = { 200, -1 }, gravity = { 0, 0.5 } })
	return result
end
