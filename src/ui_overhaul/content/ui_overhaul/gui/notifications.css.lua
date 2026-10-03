-- Notification ridge: the count badge of a group sits on the top right corner of its icon, partly
-- outside, like the gamepad hint the base puts on the bottom right corner (notifications.css.lua).
-- The badge itself is the base "bubble" (entity_window.css.lua). Members other than the shown one
-- render empty layouts next to it; no spacing, so the icon keeps the base size.
local ssu = require("::/gui/main/stylesheetutil.lua")

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
	return result
end
