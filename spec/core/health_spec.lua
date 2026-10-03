local health = require("/ux_overhaul/core/health.lua")

local function snapshot()
	return {
		finance = { cash = 500000, loan = 0, cashflow_month = 1200, cashflow_last_month = -300 },
		lines = {
			{ id = 1, name = "Bus 1", vehicle_count = 3, balance = 25000, utilization = 0.7, issues = {} },
			{ id = 2, name = "Bus 2", vehicle_count = 2, balance = -8000, utilization = 0.2, issues = {} },
			{ id = 3, name = "Rail A", vehicle_count = 0, balance = 0, issues = {} },
			{ id = 4, name = "Truck", vehicle_count = 4, balance = -1000, utilization = 0.5,
				issues = { { severity = "caution", text = "Station overcrowded" } } },
		},
		vehicles = {
			{ id = 10, name = "Bus #1", line = 1, age_years = 30, lifespan_years = 20 },
			{ id = 11, name = "Bus #2", line = 1, age_years = 5, lifespan_years = 20 },
			{ id = 12, name = "Truck #1", line = 4, age_years = 1, lifespan_years = 15, no_path = true },
		},
	}
end

describe("health", function()
	it("counts losing, empty and issue lines, old and stuck vehicles", function()
		local s = health.summarize(snapshot())
		assert.are.equal(4, s.lines)
		assert.are.equal(2, s.losing_lines)
		assert.are.equal(1, s.empty_lines)
		assert.are.equal(1, s.issue_lines)
		assert.are.equal(16000, s.lines_balance)
		assert.are.equal(1, s.old_vehicles)
		assert.are.equal(1, s.no_path_vehicles)
		assert.are.equal(-300, s.cashflow_last_month)
	end)

	it("counts problems and cautions the same way as the problem list", function()
		local s = health.summarize(snapshot())
		-- problems: 2 losing lines, 1 empty line, 1 stuck vehicle; cautions: 1 line issue, 1 old vehicle
		assert.are.equal(4, s.problems)
		assert.are.equal(2, s.cautions)
	end)

	it("ranks problems before cautions before infos, worst first", function()
		local list = health.problems(snapshot())
		local kinds = {}
		for i, item in ipairs(list) do kinds[i] = item.kind .. ":" .. tostring(item.entity) end
		assert.are.same({
			"line_losing:2", "line_losing:4", "line_empty:3", "vehicle_no_path:12",
			"vehicle_old:10", "line_issue:4",
			"line_underused:2",
		}, kinds)
	end)

	it("reports low cash only below the threshold", function()
		local s = snapshot()
		assert.are.equal(nil, health.count_by_kind(health.problems(s)).low_cash)
		s.finance.cash = -10
		assert.are.equal(1, health.count_by_kind(health.problems(s)).low_cash)
		assert.are.equal(1, health.count_by_kind(health.problems(snapshot(), { low_cash = 1e6 })).low_cash)
	end)

	it("treats vehicles without a known lifespan as not old", function()
		assert.is_false(health.is_old({ age_years = 50 }))
		assert.is_false(health.is_old({ age_years = 50, lifespan_years = 0 }))
		assert.is_true(health.is_old({ age_years = 10, lifespan_years = 20 }, 0.5))
	end)
end)
