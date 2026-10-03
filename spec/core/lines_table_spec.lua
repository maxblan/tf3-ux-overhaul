local lines_table = require("/ux_overhaul/core/lines_table.lua")

local LINES = {
	{ id = 1, name = "bus 1", carrier = "ROAD", vehicle_count = 3, balance = 25000, utilization = 0.7, issues = {} },
	{ id = 2, name = "Bus 2", carrier = "ROAD", vehicle_count = 2, balance = -8000, utilization = 0.2, issues = {} },
	{ id = 3, name = "Rail A", carrier = "RAIL", vehicle_count = 0, balance = 0, issues = {} },
	{ id = 4, name = "Truck", carrier = "ROAD", vehicle_count = 4, balance = -1000, utilization = 0.5,
		issues = { { severity = "caution", text = "x" } } },
}

local function ids(rows)
	local result = {}
	for i, row in ipairs(rows) do result[i] = row.id end
	return result
end

describe("lines_table", function()
	it("sorts by balance ascending by default, so the worst line comes first", function()
		assert.are.same({ 2, 4, 3, 1 }, ids(lines_table.rows(LINES)))
	end)

	it("sorts by any column, descending on request, ties by name", function()
		assert.are.same({ 4, 1, 2, 3 }, ids(lines_table.rows(LINES, { sort = "vehicles", descending = true })))
		assert.are.same({ 1, 2, 3, 4 }, ids(lines_table.rows(LINES, { sort = "name" })))
		assert.are.same({ 3, 1, 2, 4 }, ids(lines_table.rows(LINES, { sort = "carrier" })))
	end)

	it("filters with quick filters and a case-insensitive search", function()
		assert.are.same({ 2, 4 }, ids(lines_table.rows(LINES, { filter = "losing" })))
		assert.are.same({ 4 }, ids(lines_table.rows(LINES, { filter = "issues" })))
		assert.are.same({ 3 }, ids(lines_table.rows(LINES, { filter = "empty" })))
		assert.are.same({ 2 }, ids(lines_table.rows(LINES, { filter = "underused" })))
		assert.are.same({ 2, 1 }, ids(lines_table.rows(LINES, { search = "BUS" })))
	end)

	it("counts the lines of every quick filter", function()
		assert.are.same({ all = 4, losing = 2, issues = 1, empty = 1, underused = 1 }, lines_table.counts(LINES))
	end)

	it("totals vehicles and balance and weights utilization by vehicles", function()
		local totals = lines_table.totals(LINES)
		assert.are.equal(4, totals.lines)
		assert.are.equal(9, totals.vehicles)
		assert.are.equal(16000, totals.balance)
		assert.are.equal((0.7 * 3 + 0.2 * 2 + 0.5 * 4) / 9, totals.utilization)
		assert.are.equal(nil, lines_table.totals({}).utilization)
	end)
end)
