local line_problems = require("/ui_overhaul/core/line_problems.lua")

local W = line_problems.WAYPOINT

describe("line_problems", function()
	it("names the problem of a stop state in the base order", function()
		assert.is_nil(line_problems.kind({}))
		assert.are.equal("duplicate", line_problems.kind({ duplicate = true, noPath = true }))
		assert.are.equal("incompatible", line_problems.kind({ incompatible = true, noPath = true }))
		assert.are.equal("no_path", line_problems.kind({ noPath = true }))
		assert.are.equal("from_alternative", line_problems.kind({ fromAlternative = { 2 } }))
		assert.are.equal("from_alternative_to_alternative",
			line_problems.kind({ fromAlternative = { 2 }, toAlternative = { 3 } }))
		assert.are.equal("to_alternative", line_problems.kind({ toAlternative = { 3 } }))
	end)

	it("places a missing path at both of its terminals, wrapping at the last stop", function()
		local stops = { { name = "A", terminal0 = 0 }, { name = "B", terminal0 = 2 }, { name = "C", terminal0 = 1 } }
		local segments = { { {} }, { { noPath = true, reason = "Catenary" } }, { { noPath = true } } }
		local result = line_problems.index2problems(stops, segments)
		assert.are.same({}, result[1])
		local p = result[2][1]
		assert.are.same({ stop = 2, terminal = 3 }, p.stopAndTerminalThis)
		assert.are.same({ stop = 0, terminal = 2 }, p.stopAndTerminalNext) -- (2 + 1) % 3: base wrap
		assert.are.equal("no_path", p.kind)
		assert.are.equal("Catenary", p.params.reason)
		assert.are.equal("B", p.params.origin)
		-- last stop -> first stop
		local last = result[3][1]
		assert.are.same({ stop = 1, terminal = 1 }, last.stopAndTerminalNext)
		assert.are.equal("A", last.params.destination)
		assert.are.same(result[3], result[0])
	end)

	it("uses the alternative terminals and flags waypoints", function()
		local stops = { { name = "A", terminal0 = 0 }, { name = "wp", terminal0 = W }, { name = "B", terminal0 = 1 } }
		local segments = { { { fromAlternative = { 4, "Road" }, toAlternative = { 5 } }, { noPath = true } }, { {} } }
		local result = line_problems.index2problems(stops, segments)
		local alt = result[1][1]
		assert.are.equal("from_alternative_to_alternative", alt.kind)
		assert.are.equal(5, alt.params.terminalOrigin)
		assert.are.equal(6, alt.params.terminalDestination)
		assert.are.equal("Road", alt.params.reason)
		assert.is_true(alt.params.destinationIsWaypoint)
		local wp = result[2][1]
		assert.is_true(wp.params.originIsWaypoint)
		assert.is_false(wp.params.destinationIsWaypoint)
	end)

	it("handles lines without stops", function()
		assert.are.same({ [0] = {} }, line_problems.index2problems({}, {}))
	end)

	it("finds terminals the line's vehicles cannot use", function()
		local rail = { carriers = { RAIL = true }, passengers = true, cargo = false }
		assert.are.equal("carrier",
			line_problems.incompatibility({ carriers = { ROAD = true }, passengers = true }, rail))
		assert.is_nil(line_problems.incompatibility({ carriers = { RAIL = true }, passengers = true }, rail))
		assert.are.equal("cargo_only",
			line_problems.incompatibility({ carriers = { RAIL = true }, cargo = true }, rail))
		local freight = { carriers = { RAIL = true }, passengers = false, cargo = true }
		assert.are.equal("passengers_only",
			line_problems.incompatibility({ carriers = { RAIL = true }, passengers = true }, freight))
		-- unknown line (no vehicles): nothing to say
		assert.is_nil(line_problems.incompatibility({ carriers = { ROAD = true }, cargo = true },
			{ carriers = {}, passengers = false, cargo = false }))
		-- mixed line: either kind of terminal is fine
		assert.is_nil(line_problems.incompatibility({ carriers = { RAIL = true }, cargo = true },
			{ carriers = { RAIL = true }, passengers = true, cargo = true }))
	end)
end)
