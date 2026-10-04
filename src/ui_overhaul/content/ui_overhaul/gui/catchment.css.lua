-- Catchment toggles in the mod button area (catchment.lua): the size, padding and spacing of the
-- other buttons there (the layer button, Timetables' clock: 32 x 32 with a 24 x 24 icon).
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UioCatchmentButtons BoxLayout!uio-catchment-buttons", { innerSpacing = { 8, 0 }, margin = { 0, 0, 0, 8 } })
	add("R::UioCatchmentButtons ToggleButton!uio-catchment-toggle", {
		size = { 32, 32 }, minSize = { 32, 32 }, maxSize = { 32, 32 },
		padding = { 4, 4, 4, 4 }, margin = { 1, 1, 2, 1 }, gravity = { 0.5, 0.5 },
	})
	add("R::UioCatchmentButtons ImageView!uio-catchment-icon", {
		size = { 24, 24 }, minSize = { 24, 24 }, maxSize = { 24, 24 }, gravity = { 0.5, 0.5 },
	})
	return result
end
