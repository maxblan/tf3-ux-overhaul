-- Catchment toggles in the mod button area (catchment.lua): each its own plugin, with the size,
-- padding and margins of the other buttons there (Timetables' clock: a 32 x 32 toggle with a 24 x 24
-- icon and margins 1, 1, 2, 1), so the area spaces all of them alike.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("ToggleButton!uio-catchment-toggle", {
		size = { 32, 32 }, minSize = { 32, 32 }, maxSize = { 32, 32 },
		padding = { 4, 4, 4, 4 }, margin = { 1, 1, 2, 1 }, gravity = { 0.5, 0.5 },
	})
	add("ToggleButton!uio-catchment-toggle ImageView!uio-catchment-icon", {
		size = { 24, 24 }, minSize = { 24, 24 }, maxSize = { 24, 24 }, gravity = { 0.5, 0.5 },
	})
	return result
end
