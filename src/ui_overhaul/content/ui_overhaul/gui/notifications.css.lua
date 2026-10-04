-- Notification ridge: the count badge of a group sits on the top right corner of its icon, partly
-- outside, like the gamepad hint the base puts on the bottom right corner (notifications.css.lua).
-- The badge itself is the base "bubble" (entity_window.css.lua). Members other than the shown one
-- render empty layouts next to it; no spacing, so the icon keeps the base size.
-- Subsidy icons (notifications.lua): state colours from the game's own palette for completed (green)
-- and missed (grey) subsidies, and a timer ring in plain white (base: 75 % white).
local ssu = require("::/gui/main/stylesheetutil.lua")
local color_util = require("::/gui/main/color_util.tl")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::NotificationPopups R::NotificationIcon TextView!bubble!uio-notification-count", {
		gravity = { 1.0, 0.0 },
		anchorPoint = { 0.7, 0.3 },
	})
	add("R::NotificationPopups R::NotificationIcon BoxLayout!uio-notification-members", {
		innerSpacing = { 0, 0 },
	})

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local function state_colour(class, colour)
		local base = "R::Component!" .. class .. " R::NotificationProgressIcon R::Component!opportunity, "
			.. "R::Component!" .. class .. " R::NotificationSimpleIcon ImageView!opportunity"
		add(base, { backgroundColor1 = colour })
		local hover = base:gsub(", ", ", Button:hover ")
		local active = base:gsub(", ", ", Button:active ")
		add("Button:hover " .. hover, { backgroundColor1 = color_util.getHoverFromRaw(colour) })
		add("Button:active " .. active, { backgroundColor1 = color_util.getActiveFromRaw(colour) })
	end
	state_colour("uio-subsidy-complete", colorDefault.Ok)
	state_colour("uio-subsidy-missed", colorDefault.NeutralDark)

	-- subsidy timer rings in plain white instead of the game's 75 % white, nothing else changes colour
	for _i, class in ipairs({ "uio-subsidy-offer", "uio-subsidy-active", "uio-subsidy-complete" }) do
		add("R::Component!" .. class .. " R::NotificationProgressIcon ImageView!progress",
			{ color = colorDefault.NeutralLightest })
	end
	return result
end
