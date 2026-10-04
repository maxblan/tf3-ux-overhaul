--- Slider helpers: mouse-wheel steps and typed values. Pure Lua.
-- @module ui_overhaul.core.slider_values
local slider_values = {}

--- `value` moved onto the slider's grid (min + k x step) and into min..max.
---@param value number
---@param min number
---@param max number
---@param step? number
---@return number
function slider_values.on_grid(value, min, max, step)
	step = (step and step > 0) and step or 1
	local v = min + math.floor((value - min) / step + 0.5) * step
	if v < min then v = min end
	if v > max then v = max end
	return v
end

---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
	if value < min then return min end
	if value > max then return max end
	return value
end

--- The value after one wheel notch in direction `dir` (+1 up, -1 down): one step, within min..max.
---@param value number
---@param min number
---@param max number
---@param step? number
---@param dir number +1 up, -1 down
---@return number
function slider_values.wheel(value, min, max, step, dir)
	step = (step and step > 0) and step or 1
	return clamp(value + dir * step, min, max)
end

--- The first number in a text as the game shows values ("2,5 m", "-3 %", "1.5x"); nil if none.
-- A comma is read as the decimal point.
---@param text string? anything but a string gives nil
---@return number?
function slider_values.parse_number(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("\xE2\x88\x92", "-") -- typographic minus
	local number = text:match("[-+]?%d+[.,]?%d*") ---@type string?
	if not number then return nil end
	number = number:gsub(",", ".")
	return tonumber(number)
end

--- Index (1-based) of the entry of `labels` (the texts a slider shows for each of its positions)
-- that best matches what the player typed: the nearest number, or the first label starting with the
-- text; nil if nothing matches.
---@param labels string[]
---@param typed string?
---@return integer?
function slider_values.nearest_label(labels, typed)
	local wanted = slider_values.parse_number(typed)
	if wanted then
		local best, best_distance ---@type integer?, number
		for i, label in ipairs(labels) do
			local number = slider_values.parse_number(label)
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

return slider_values
