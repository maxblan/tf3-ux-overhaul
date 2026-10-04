local geometry = require("/ui_overhaul/core/geometry.lua")

local function v(x, y, z) return { x = x, y = y, z = z or 0 } end

-- Hermite tangent length of a quarter circle: 3 x the Bezier handle 0.5523 R.
local K = 3 * 0.5523

local function quarter_circle(r, z0, z1)
	return { p0 = v(r, 0, z0), p1 = v(0, r, z1), t0 = v(0, K * r, z1 - z0), t1 = v(-K * r, 0, z1 - z0) }
end

describe("geometry", function()
	it("measures a straight rising edge", function()
		local m = geometry.edge_metrics({ p0 = v(0, 0, 0), p1 = v(100, 0, 3), t0 = v(100, 0, 3), t1 = v(100, 0, 3) })
		assert.is_true(math.abs(m.max_grade - 0.03) < 1e-6)
		assert.are.equal(math.huge, m.min_radius)
		assert.is_true(math.abs(m.length - math.sqrt(100 * 100 + 9)) < 1e-3)
		assert.are.equal(0, m.z_min)
		assert.is_true(math.abs(m.z_max - 3) < 1e-9)
	end)

	it("finds the radius of a curve", function()
		local m = geometry.edge_metrics(quarter_circle(300, 0, 0))
		assert.is_true(math.abs(m.min_radius - 300) / 300 < 0.02, "radius " .. m.min_radius)
		assert.is_true(math.abs(m.length - math.pi / 2 * 300) / 300 < 0.01, "length " .. m.length)
		assert.are.equal(0, m.max_grade)
	end)

	it("summarises the drawn edges and skips parts of a split existing edge", function()
		local existing = { p0 = v(0, 0), p1 = v(200, 0), t0 = v(200, 0), t1 = v(200, 0) }
		local part = { p0 = v(0, 0), p1 = v(100, 0), t0 = v(100, 0), t1 = v(100, 0) }
		local drawn = quarter_circle(150, 0, 6)
		local s = geometry.summary({ part, drawn }, { existing })
		assert.are.equal(1, s.count)
		assert.is_true(math.abs(s.min_radius - 150) / 150 < 0.05)
		assert.is_true(s.max_grade > 0.02 and s.max_grade < 0.05, "grade " .. s.max_grade)
		assert.are.equal(0, s.z_min)
		assert.is_true(math.abs(s.z_max - 6) < 1e-9)
		assert.is_nil(geometry.summary({ part }, { existing }))
		assert.is_nil(geometry.summary({}, {}))
	end)
end)
