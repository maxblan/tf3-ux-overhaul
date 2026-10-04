--- Top speed of a train on three slopes and how long it takes to reach it, as the game computes it
-- for the store's performance rating (gui/line_vehicle_mgmt/vehicle_util.tl,
-- getPowerRatingTextAndToolTip), but as numbers instead of one preformatted text. Pure Lua; the
-- integrator is handed in (the game's Romberg integration in the game, Simpson's rule in the specs).
-- @module ui_overhaul.core.vehicle_slopes
local vehicle_slopes = {}

vehicle_slopes.SLOPES = { 0, 0.0375, 0.075 } -- the game's flat, medium and high slope
local G = 3.27 -- the game's constant (calcDownhillSlopeForce)

local function tractive_effort(power, effort, speed)
	if effort == 0 then return 0 end
	if speed <= power / effort then return effort end
	return power / speed
end

local function slope_force(slope, weight)
	return G * slope * weight
end

--- Simpson's rule over [a, b] with n (even) intervals: { integral, error estimate 0 }.
function vehicle_slopes.simpson(a, b, fn, n)
	n = n or 400
	local h = (b - a) / n
	local sum = fn(a) + fn(b)
	for i = 1, n - 1 do
		sum = sum + fn(a + i * h) * ((i % 2 == 1) and 4 or 2)
	end
	return { sum * h / 3, 0 }
end

--- One row per slope: { slope, enough = bool, speed, time, distance } (speed in the game's unit,
-- time in seconds, distance in metres), and the rating index 1..4 (Poor, Mediocre, Good,
-- Excellent). `v` = { weight, power, tractiveEffort, speed, rollingFriction }. `integrate(a, h, tol,
-- fn)` returns { value, error }; nil means the game's formula gives up (returns nil).
function vehicle_slopes.compute(v, integrate)
	integrate = integrate or function(a, h, _tol, fn) return vehicle_slopes.simpson(a, a + h, fn) end
	local rows, feasible = {}, 1
	for i, slope in ipairs(vehicle_slopes.SLOPES) do
		local traction = slope_force(slope, v.weight) + v.rollingFriction
		if traction > 0.95 * v.tractiveEffort then
			rows[i] = { slope = slope, enough = false }
		else
			local max_speed = math.min(v.speed, 0.95 * v.power / traction)
			local t = integrate(0.0, max_speed, 1.0, function(speed)
				return v.weight / (tractive_effort(v.power, v.tractiveEffort, speed) - traction)
			end)
			local s = integrate(0.0, max_speed, 10.0, function(speed)
				return speed * v.weight / (tractive_effort(v.power, v.tractiveEffort, speed) - traction)
			end)
			if t[2] < 0 or s[2] < 0 then return nil end
			rows[i] = { slope = slope, enough = true, speed = max_speed, time = t[1], distance = s[1] }
			local threshold = slope_force(slope + 0.0375 * 0.33, v.weight) + v.rollingFriction
			if math.min(v.speed, 0.95 * v.power / threshold) == v.speed then feasible = i + 1 end
		end
	end
	return rows, feasible
end

return vehicle_slopes
