--- Slider helpers: snap points ("detents"), mouse-wheel steps and typed values. Pure Lua.
--
-- Detents are round values every few percent of the range (5, 10, 25, 50 ... as fits), so a slider
-- of 0..100 snaps to every 5, one of 0..600 seconds to every 30 or 50. Snapping is magnetic: a value
-- within 30 % of a detent interval jumps to the detent, anything else stays as dragged, and the
-- game's precision key turns it off. Ranges with few steps (up to 20) need no detents: every step
-- already is one.
-- @module ui_overhaul.core.slider_snap
local slider_snap = {}

local MAX_DETENTS = 20 -- at most this many intervals across the range (about every 5 %)
local NICE = { 1, 2, 2.5, 5 }
local MAGNET = 0.3 -- share of a detent interval within which a dragged value jumps to the detent

--- Detent interval for a slider of min..max moving in `step`s: the smallest round multiple of
-- `step` that splits the range into at most 20 intervals; nil when the range has 20 steps or fewer.
function slider_snap.detent(min, max, step)
	step = (step and step > 0) and step or 1
	local range = max - min
	if range <= 0 or range / step <= MAX_DETENTS then return nil end
	local magnitude = 1
	while true do
		for _i, nice in ipairs(NICE) do
			local interval = nice * magnitude
			-- a multiple of the step, so a detent is a value the slider can take
			if interval >= step and math.abs(interval / step - math.floor(interval / step + 0.5)) < 1e-9
				and range / interval <= MAX_DETENTS then
				return interval
			end
		end
		magnitude = magnitude * 10
	end
end

local function clamp(value, min, max)
	if value < min then return min end
	if value > max then return max end
	return value
end

--- The value a dragged slider takes: the nearest detent if `value` is within 30 % of an interval
-- of it, else `value`. Detents count from `anchor` (default `min`). No detent interval: `value`.
function slider_snap.snap(value, min, max, detent, anchor)
	if not detent then return value end
	anchor = anchor or min
	local nearest = anchor + math.floor((value - anchor) / detent + 0.5) * detent
	nearest = clamp(nearest, min, max)
	if math.abs(value - nearest) <= detent * MAGNET then return nearest end
	return value
end

--- Detent interval (in positions) for a slider that moves through `count` evenly spaced values,
-- anchored at position `anchor` (the neutral value, e.g. 0 % incline): the first of 5, 4, 2 that
-- puts a detent on the anchor and gives at most 20 intervals; nil for 12 positions
-- or fewer, which need none.
function slider_snap.index_detent(count, anchor)
	if count <= 12 then return nil end
	anchor = anchor or 1
	for _i, d in ipairs({ 5, 4, 2, 10 }) do
		if (anchor - 1) % d == 0 and (count - 1) / d <= MAX_DETENTS then return d end
	end
	return nil
end

--- Whether `numbers` are evenly spaced (within 1 %), so positions can carry detents.
function slider_snap.evenly_spaced(numbers)
	if #numbers < 3 then return false end
	local step = numbers[2] - numbers[1]
	if step == 0 then return false end
	for i = 3, #numbers do
		if math.abs((numbers[i] - numbers[i - 1]) - step) > math.abs(step) * 0.01 then return false end
	end
	return true
end

--- The value after one wheel notch in direction `dir` (+1 up, -1 down): to the next detent (counted
-- from `anchor`, default `min`), or one step with `precise` (the game's precision key) or without
-- detents.
function slider_snap.wheel(value, min, max, step, detent, dir, precise, anchor)
	step = (step and step > 0) and step or 1
	if precise or not detent then return clamp(value + dir * step, min, max) end
	anchor = anchor or min
	local position = (value - anchor) / detent
	local target
	if dir > 0 then
		target = math.floor(position + 1e-9) + 1
	else
		target = math.ceil(position - 1e-9) - 1
	end
	return clamp(anchor + target * detent, min, max)
end

--- The first number in a text as the game shows values ("2,5 m", "-3 %", "1.5x"); nil if none.
-- A comma is read as the decimal point.
function slider_snap.parse_number(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("\xE2\x88\x92", "-") -- typographic minus
	local number = text:match("[-+]?%d+[.,]?%d*")
	if not number then return nil end
	number = number:gsub(",", ".")
	return tonumber(number)
end

--- Index (1-based) of the entry of `labels` (the texts a slider shows for each of its positions)
-- that best matches what the player typed: the nearest number, or the first label starting with the
-- text; nil if nothing matches.
function slider_snap.nearest_label(labels, typed)
	local wanted = slider_snap.parse_number(typed)
	if wanted then
		local best, best_distance
		for i, label in ipairs(labels) do
			local number = slider_snap.parse_number(label)
			if number then
				local distance = math.abs(number - wanted)
				if not best or distance < best_distance then best, best_distance = i, distance end
			end
		end
		if best then return best end
	end
	if type(typed) ~= "string" or typed == "" then return nil end
	local lower = typed:lower()
	for i, label in ipairs(labels) do
		if tostring(label):lower():sub(1, #lower) == lower then return i end
	end
	return nil
end

return slider_snap
