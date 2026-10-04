--- Test site: flat dry land for the scenarios.
--
-- Scenario areas are SITE_LENGTH long along +x (from X_MIN to X_MAX relative to the site origin)
-- and lie next to each other along +y, GAP apart.
-- @module ui_overhaul_testbench.site
local site = {}

site.X_MIN, site.X_MAX = -300, 300
site.GAP = 80

local FLAT_ENOUGH = 3.0 -- m height range over the whole site
local SEARCH_STEP = 150
local SEARCH_RINGS = 12

---@param x number
---@param y number
---@return Vec2f
local function vec2(x, y)
	return api.type.Vec2f.new(x, y)
end

--- Terrain height (without terrain alignments) at x, y.
---@param x number
---@param y number
---@return number
function site.height(x, y)
	return api.engine.terrain.getBaseHeightAt(vec2(x, y))
end

-- Height range and lowest height of the area, or nil if it contains water, leaves the map or
-- is clearly too rough.
---@param x number
---@param y number
---@param width number
---@return number? range
---@return number? lowest
local function roughness(x, y, width)
	local lo, hi = math.huge, -math.huge
	for dx = site.X_MIN, site.X_MAX, 60 do
		for dy = 0, width, 35 do
			local p = vec2(x + dx, y + dy)
			if not api.engine.terrain.isValidCoordinate(p) or api.engine.terrain.isOnWater(p) then return nil end
			local h = site.height(x + dx, y + dy)
			lo, hi = math.min(lo, h), math.max(hi, h)
			if hi - lo > 4 * FLAT_ENOUGH then return nil end
		end
	end
	return hi - lo, lo
end

--- Flattest site for `count` scenarios, searched in rings from the map centre outwards.
-- Returns { x, y, range, base } or nil. Searching is cheap enough to run in one update().
---@param count integer
---@return uo.testbench.Site?
function site.find(count)
	local box = api.engine.terrain.getBoundingBox()
	local center_x, center_y = (box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2
	local width = count * site.GAP
	local best ---@type uo.testbench.Site?
	for ring = 0, SEARCH_RINGS do
		for ix = -ring, ring do
			for iy = -ring, ring do
				if math.max(math.abs(ix), math.abs(iy)) == ring then
					local x, y = center_x + ix * SEARCH_STEP, center_y + iy * SEARCH_STEP - width / 2
					local range, base = roughness(x, y, width)
					if range and base and (not best or range < best.range) then -- base is set whenever range is
						best = { x = x, y = y, range = range, base = base }
					end
				end
			end
		end
		if best and best.range <= FLAT_ENOUGH then break end
	end
	return best
end

---@class uo.testbench.Area
---@field x number
---@field y number
---@field base number terrain height

---@class uo.testbench.Site: uo.testbench.Area
---@field range number terrain height range over the site, m

--- Origin { x, y, base } of the area of the scenario with the given index.
---@param found uo.testbench.Site
---@param index integer
---@return uo.testbench.Area
function site.area(found, index)
	return { x = found.x, y = found.y + (index - 1) * site.GAP, base = found.base }
end

return site
