--- Measurements of track and road edges for the construction tooltip: gradient, curve radius and
-- height. An edge is a cubic Hermite curve between its two node positions with the tangents of its
-- BaseEdge component (the transport network's edge model). Points and vectors are plain tables
-- { x, y, z }. Pure Lua.
-- @module ui_overhaul.core.geometry
local geometry = {}

local SAMPLES = 16 -- per edge; edges are short enough that this finds the tightest point

--- Position, first and second derivative of the edge `e` = { p0, p1, t0, t1 } at s in [0, 1].
function geometry.hermite(e, s)
	local s2, s3 = s * s, s * s * s
	local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
	local d00, d10, d01, d11 = 6 * s2 - 6 * s, 3 * s2 - 4 * s + 1, 6 * s - 6 * s2, 3 * s2 - 2 * s
	local a00, a10, a01, a11 = 12 * s - 6, 6 * s - 4, 6 - 12 * s, 6 * s - 2
	local function combine(c00, c10, c01, c11)
		return {
			x = c00 * e.p0.x + c10 * e.t0.x + c01 * e.p1.x + c11 * e.t1.x,
			y = c00 * e.p0.y + c10 * e.t0.y + c01 * e.p1.y + c11 * e.t1.y,
			z = c00 * e.p0.z + c10 * e.t0.z + c01 * e.p1.z + c11 * e.t1.z,
		}
	end
	return combine(h00, h10, h01, h11), combine(d00, d10, d01, d11), combine(a00, a10, a01, a11)
end

--- Horizontal curve radius at a point with first and second derivative d1, d2 (math.huge if straight).
local function radius(d1, d2)
	local speed2 = d1.x * d1.x + d1.y * d1.y
	local cross = math.abs(d1.x * d2.y - d1.y * d2.x)
	if cross < 1e-9 or speed2 < 1e-12 then return math.huge end
	return speed2 ^ 1.5 / cross
end

--- { length, max_grade, min_radius, z_min, z_max, points } of edge `e`: length along the curve,
-- the steepest gradient (rise per horizontal distance, a fraction), the tightest horizontal radius
-- (math.huge for a straight edge), the height range, and the sampled points.
function geometry.edge_metrics(e)
	local m = { length = 0, max_grade = 0, min_radius = math.huge, z_min = math.huge, z_max = -math.huge, points = {} }
	local previous
	for i = 0, SAMPLES do
		local s = i / SAMPLES
		local p, d1, d2 = geometry.hermite(e, s)
		m.points[#m.points + 1] = p
		local horizontal = math.sqrt(d1.x * d1.x + d1.y * d1.y)
		if horizontal > 1e-9 then m.max_grade = math.max(m.max_grade, math.abs(d1.z) / horizontal) end
		-- the ends of a curve can carry the neighbour's curvature; the tightest point is inside
		m.min_radius = math.min(m.min_radius, radius(d1, d2))
		m.z_min, m.z_max = math.min(m.z_min, p.z), math.max(m.z_max, p.z)
		if previous then
			local dx, dy, dz = p.x - previous.x, p.y - previous.y, p.z - previous.z
			m.length = m.length + math.sqrt(dx * dx + dy * dy + dz * dz)
		end
		previous = p
	end
	return m
end

--- Whether `point` lies on edge `e` (within `eps` metres): finds the new parts of an existing edge
-- that a proposal splits.
function geometry.on_edge(point, e, eps)
	eps = eps or 0.5
	local best = math.huge
	local steps = SAMPLES * 4
	for i = 0, steps do
		local p = geometry.hermite(e, i / steps)
		local dx, dy, dz = p.x - point.x, p.y - point.y, p.z - point.z
		best = math.min(best, dx * dx + dy * dy + dz * dz)
	end
	return best <= eps * eps
end

--- The edges a player draws: `edges` (the proposal's new edges) without those lying on one of
-- `removed` (the edges the proposal removes), which are parts of a split existing edge.
function geometry.drawn(edges, removed)
	local result = {}
	for _i, e in ipairs(edges) do
		local split = false
		for _j, old in ipairs(removed or {}) do
			if geometry.on_edge(e.p0, old) and geometry.on_edge(e.p1, old) then split = true break end
		end
		if not split then result[#result + 1] = e end
	end
	return result
end

--- Summary of the edges a player draws (see geometry.drawn): nil without any, else
-- { length, max_grade, min_radius, z_min, z_max, count }.
function geometry.summary(edges, removed)
	local result
	for _i, e in ipairs(geometry.drawn(edges, removed)) do
		local m = geometry.edge_metrics(e)
		result = result or { length = 0, max_grade = 0, min_radius = math.huge, z_min = math.huge,
			z_max = -math.huge, count = 0 }
		result.length = result.length + m.length
		result.max_grade = math.max(result.max_grade, m.max_grade)
		result.min_radius = math.min(result.min_radius, m.min_radius)
		result.z_min, result.z_max = math.min(result.z_min, m.z_min), math.max(result.z_max, m.z_max)
		result.count = result.count + 1
	end
	return result
end

return geometry
