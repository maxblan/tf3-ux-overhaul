local vehicle_slopes = require("/ui_overhaul/core/vehicle_slopes.lua")

describe("vehicle_slopes", function()
	-- a light, strong train: full speed on every slope
	local strong = { weight = 100, power = 2000, tractiveEffort = 200, speed = 30, rollingFriction = 1 }
	-- a heavy, weak one: slower uphill, stuck on the steep slope
	local weak = { weight = 1000, power = 2000, tractiveEffort = 200, speed = 30, rollingFriction = 5 }

	it("reaches full speed everywhere with enough power", function()
		local rows, rating = vehicle_slopes.compute(strong)
		assert(rows and rating)
		assert.are.equal(4, rating)
		for _i, row in ipairs(rows) do
			assert.is_true(row.enough)
			assert.are.equal(30, row.speed)
			assert.is_true(row.time > 0 and row.distance > 0)
		end
		-- steeper takes longer
		assert.is_true(rows[3].time > rows[1].time)
	end)

	it("slows down and stops on slopes it cannot climb", function()
		local rows, rating = vehicle_slopes.compute(weak)
		assert(rows and rating)
		assert.is_true(rows[1].enough)
		assert.is_true(rows[2].enough)
		assert.is_true(rows[2].speed < 30)
		assert.is_false(rows[3].enough) -- 3.27 * 0.075 * 1000 + 5 > 0.95 * 200
		assert.is_true(rating < 4)
	end)

	it("gives up as the game does when the integration fails", function()
		local failing = function() return { 0, -1 } end
		assert.is_nil(vehicle_slopes.compute(strong, failing))
	end)
end)
