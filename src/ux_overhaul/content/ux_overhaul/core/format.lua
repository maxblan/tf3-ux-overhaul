--- Compact number formatting for dense status displays. Full money values use the engine's
-- api.util.formatMoney in the GUI; these helpers are for chips and table cells. Pure Lua.
-- @module ux_overhaul.core.format
local format = {}

local MINUS = "\xE2\x88\x92" -- typographic minus, same width as "+"

local function trim(text)
	-- "1.0k" -> "1k", "12.50" stays "12.5" (callers format with one decimal at most)
	return (text:gsub("%.0([kMB]?)$", "%1"))
end

--- 950 -> "950", 1234 -> "1.2k", 25300 -> "25k", 1234567 -> "1.2M", -5000 -> "−5k".
function format.compact(value)
	value = value or 0
	local sign = value < 0 and MINUS or ""
	local abs = math.abs(value)
	local text
	if abs < 1000 then
		text = string.format("%d", math.floor(abs + 0.5))
	elseif abs < 10000 then
		text = trim(string.format("%.1fk", abs / 1000))
	elseif abs < 1000000 then
		text = string.format("%dk", math.floor(abs / 1000 + 0.5))
	elseif abs < 10000000 then
		text = trim(string.format("%.1fM", abs / 1000000))
	elseif abs < 1000000000 then
		text = string.format("%dM", math.floor(abs / 1000000 + 0.5))
	else
		text = trim(string.format("%.1fB", abs / 1000000000))
	end
	return sign .. text
end

--- Like compact, with an explicit "+" for positive values (for balances and cash flow).
function format.signed(value)
	value = value or 0
	if value > 0 then return "+" .. format.compact(value) end
	return format.compact(value)
end

--- 0.456 -> "46%", nil -> "–".
function format.percent(ratio)
	if ratio == nil then return "\xE2\x80\x93" end
	return string.format("%d%%", math.floor(ratio * 100 + 0.5))
end

return format
