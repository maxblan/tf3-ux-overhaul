-- Column widths of the mod's line-window stops table, matching the vanilla vehicle table next to it
-- (entity_window.css.lua: vehicle cell 300, age cell 98).
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UioStopsTable R::UioStopCell", { size = { 300, -1 } })
	add("R::UioStopsTable R::UioStopWaitingCell", { size = { 98, -1 } })
	-- fixed widths like the vanilla vehicle cell (NameTextView 180 there), so the pins line up
	add("R::UioStopCell TextView!uio-stop-index", { size = { 34, -1 }, maxSize = { 34, -1 } })
	add("R::UioStopsTable R::UioStopCell R::NameTextView", { size = { 230, -1 }, maxSize = { 230, -1 } })
	return result
end
