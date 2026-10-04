local development = require("/ui_overhaul/core/industry_development.lua")

describe("industry_development", function()
	it("computes the game's expansion chance", function()
		assert.are.equal(0, development.chance(1, 0, 100))
		assert.are.equal(1, development.chance(1, 100, 100))
		assert.are.equal(1, development.chance(1, 200, 100)) -- shipping more than the output counts as all
		local chance, rating = development.chance(0.8, 50, 100)
		assert.is_true(math.abs(rating - 0.4) < 1e-9)
		assert.is_true(math.abs(chance - 0.3) < 1e-9)
		assert.are.equal(0, development.chance(1, 10, 0))
	end)

	it("names what keeps an industry from expanding", function()
		assert.are.same({ "max_level" }, development.blockers({ level = 3, maxLevel = 3, manual = true }))
		assert.are.same({}, development.blockers({ level = 1, maxLevel = 3, output = 100, chance = 0.5 }))
		assert.are.same({ "not_shipped" }, development.blockers({ level = 1, maxLevel = 3, output = 100, chance = 0 }))
		assert.are.same({ "no_output", "blocked" },
			development.blockers({ level = 1, maxLevel = 3, output = 0, blocked = true, chance = 0 }))
		assert.are.same({ "manual", "player_owned", "closing" },
			development.blockers({ level = 1, maxLevel = 3, output = 10, manual = true, playerOwned = true, closing = true }))
	end)
end)
