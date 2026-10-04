-- Catchment toggles in the mod button area (catchment.lua): small icon toggles like the layer
-- filter toggles (layers.css.lua), side by side.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("BoxLayout!uio-catchment-buttons", { innerSpacing = { 4, 0 } })
	add("ToggleButton!uio-catchment-toggle", { size = { 32, 32 }, padding = { 4, 4, 4, 4 } })
	return result
end
