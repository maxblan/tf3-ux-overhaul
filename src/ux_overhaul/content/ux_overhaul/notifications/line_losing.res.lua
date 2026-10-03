-- Notification type of UX Overhaul; the GUI side is line_losing.script.lua.
function data()
	return {
		type = "notification",
		data = {
			guiType = "Problem",
			label = _("Line Loses Money"),
			initiallyIgnoredType = false,
		},
	}
end
