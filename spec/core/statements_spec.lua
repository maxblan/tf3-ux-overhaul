local statements = require("/ui_overhaul/core/statements.lua")

local enum = { INCOME = 1, MAINTENANCE = 2, ACQUISITION = 3, CONSTRUCTION = 4, SUBSIDY = 5,
	VEHICLE = 11, INFRASTRUCTURE = 12, VEHICLE_MAINTENANCE = 13 }

---@alias uo.spec.statements.Row uo.core.statements.Row

---@param rows uo.spec.statements.Row[]
---@param key string
---@return uo.spec.statements.Row?
local function row(rows, key)
	for _i, r in ipairs(rows) do
		if r.key == key then return r end
	end
end

--- The row that must be there.
---@param rows uo.spec.statements.Row[]
---@param key string
---@return uo.spec.statements.Row
local function get(rows, key)
	return assert(row(rows, key), key)
end

describe("statements", function()
	local data = {
		columns = 2,
		entries = {
			{ 1, 0, { 1000, 1200 } }, -- revenue, two carriers
			{ 1, 0, { 500, 300 } },
			{ 2, 11, { -300, -350 } }, -- running costs
			{ 2, 12, { -100, -100 } }, -- upkeep
			{ 3, 0, { -2000, 0 } }, -- vehicles bought
			{ 4, 0, { 0, -400 } }, -- construction
		},
		other = { 0, 0 },
		interest = { -50, -40 },
	}

	it("builds the income statement", function()
		local income = statements.income(data, enum)
		assert.are.same({ 1500, 1500 }, get(income, "revenue").values)
		assert.are.same({ 1100, 1050 }, get(income, "operating_result").values)
		assert.are.same({ 1050, 1010 }, get(income, "net_income").values)
		assert.is_nil(row(income, "subsidies")) -- no values: left out
		-- vehicles bought and construction are investments, not other income or costs
		assert.is_nil(row(income, "other"))
		assert.is_true(row(income, "operating_result") ~= nil) -- totals always stay
	end)
end)
