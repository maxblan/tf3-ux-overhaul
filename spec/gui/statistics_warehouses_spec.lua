-- statistics_warehouses.lua: the pure parts (cargo order, filters). The base modules it requires are
-- stand-ins, restored after loading so other specs keep theirs.
local stand_ins = {
	["::/gui/main/builtin.lua"] = {},
	["::/gui/main/cargo_react_util.tl"] = {},
	["::/gui/main/cargo_util.tl"] = {},
	["::/gui/main/engine_react_util.tl"] = {},
	["::/gui/main/gui_react_util.tl"] = {},
	["::/scripts/lang_util.tl"] = {},
	["::/gui/line_vehicle_mgmt/line_react_util.tl"] = {},
	["::/game_mechanics/notifications/notification_util.tl"] = {},
	["::/gui/main/react.lua"] = { RegisterRecipe = function(_name, fn) return fn end },
	["::/gui/statistics/statistics_react_util.tl"] = {},
	["::/scripts/table_util.tl"] = {},
	["::/gui/statistics/statistic_warehouses.tl"] = function() end,
}
local saved = {}
for path, module in pairs(stand_ins) do
	saved[path] = package.loaded[path]
	package.loaded[path] = module
end
local warehouses = require("/ui_overhaul/gui/statistics_warehouses.lua")
for path in pairs(stand_ins) do package.loaded[path] = saved[path] end

describe("statistics warehouses", function()
	it("lists cargo by quantity, largest first", function()
		local cargos = warehouses.sort_cargos({ { 3, 10 }, { 1, 50 }, { 2, 10 } })
		assert.are.same({ { 1, 50 }, { 2, 10 }, { 3, 10 } }, cargos)
	end)

	it("filters by fill level and cargo", function()
		local full = { stored = 95, capacity = 100, cargos = { { 4, 95 } }, takes = { [4] = true } }
		local empty = { stored = 0, capacity = 100, cargos = {}, takes = { [7] = true } }
		local any = { stored = 0, capacity = 50, cargos = {}, takes = {}, all = true }
		assert.is_true(warehouses.passes(full, "full", -1))
		assert.is_false(warehouses.passes(empty, "full", -1))
		assert.is_true(warehouses.passes(empty, "empty", -1))
		assert.is_false(warehouses.passes(full, "empty", -1))
		assert.is_true(warehouses.passes(full, "all", 4))
		assert.is_false(warehouses.passes(full, "all", 7))
		assert.is_true(warehouses.passes(empty, "all", 7)) -- takes it, holds none yet
		assert.is_true(warehouses.passes(any, "all", 9)) -- takes every cargo
		assert.are.equal(95, warehouses.count_of(full, 4))
		assert.are.equal(0, warehouses.count_of(full, 5))
	end)
end)
