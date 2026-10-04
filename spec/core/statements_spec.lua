local statements = require("/ui_overhaul/core/statements.lua")

local enum = { INCOME = 1, MAINTENANCE = 2, ACQUISITION = 3, CONSTRUCTION = 4, SUBSIDY = 5,
	VEHICLE = 11, INFRASTRUCTURE = 12, VEHICLE_MAINTENANCE = 13 }

local function row(rows, key)
	for _i, r in ipairs(rows) do
		if r.key == key then return r end
	end
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
		loanBorrowing = { 3000, 0 },
		loanRepayment = { 0, -500 },
		balance = { 5000, 4110 },
	}

	it("builds the income statement", function()
		local income = statements.build(data, enum)
		assert.are.same({ 1500, 1500 }, row(income, "revenue").values)
		assert.are.same({ 1100, 1050 }, row(income, "operating_result").values)
		assert.are.same({ 1050, 1010 }, row(income, "net_income").values)
		assert.is_nil(row(income, "subsidies")) -- no values: left out
		assert.is_nil(row(income, "other"))
		assert.is_true(row(income, "operating_result") ~= nil) -- totals always stay
	end)

	it("builds the cash flow statement", function()
		local _income, cash = statements.build(data, enum)
		assert.are.same({ -2000, -400 }, row(cash, "investing").values)
		assert.are.same({ 3000, -500 }, row(cash, "financing").values)
		assert.are.same({ 2050, 110 }, row(cash, "change").values)
		assert.are.same({ 5000, 4110 }, row(cash, "bank_account").values)
	end)

	it("builds the balance sheet", function()
		local sheet = statements.balance_sheet({ cash = 1000, vehicles = 3000, assets = 10000, debt = 4000 })
		assert.are.equal(3000, row(sheet, "vehicle_assets").value)
		assert.are.equal(7000, row(sheet, "other_assets").value)
		assert.are.equal(11000, row(sheet, "total_assets").value)
		assert.are.equal(-4000, row(sheet, "debt").value)
		assert.are.equal(7000, row(sheet, "equity").value)
		-- unlimited money: no cash figure
		local free = statements.balance_sheet({ cash = nil, vehicles = 10, assets = 5, debt = 0 })
		assert.is_nil(row(free, "cash").value)
		assert.are.equal(5, row(free, "vehicle_assets").value) -- never more than the assets
	end)
end)
