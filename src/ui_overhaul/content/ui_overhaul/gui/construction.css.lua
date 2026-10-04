-- Construction settings stay clear of the game bar at large UI and text scales.
-- The base panels have fixed pixel sizes (construction.css.lua): the bottom-left settings panel is
-- anchored to the bottom of the screen with 64 px of padding under its last row (the bridge, tunnel
-- and crossing buttons), which the Account and company buttons of the game bar (91 and 100 px
-- high, drawn on top) only just clear; it has no height limit, so a tall tool pushes its rows under
-- the game bar or off the top of the screen. The Settings window is 460 px high above a 360 px
-- margin, more than a small screen at a large UI scale offers.
-- Here both get a height limit relative to the screen, so their scroll areas scroll instead, and the
-- bottom panel more room above the game bar when the text is scaled up.
local ssu = require("::/gui/main/stylesheetutil.lua")

local BOTTOM_PARAMS = "R::ConstructionParamsContent#menu.construction.bottomparams.react"

function data()
	local result = {}
	local add = ssu.makeAdder(result)

	-- the base rule sets the same width; the extra ancestor class makes this rule win
	add("!tool-Construction " .. BOTTOM_PARAMS, { maxSize = { 314, "70vh" } })
	add(BOTTOM_PARAMS, { maxSize = { 314, "70vh" } })
	add("!font-medium " .. BOTTOM_PARAMS, { padding = { 8, 8, 76, 8 } })
	add("!font-large " .. BOTTOM_PARAMS, { padding = { 8, 8, 88, 8 } })

	add("Window!construct-settings", { maxSize = { 400, "45vh" } })
	return result
end
