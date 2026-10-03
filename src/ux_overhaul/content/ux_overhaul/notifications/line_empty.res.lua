-- Notification type of UX Overhaul; the GUI side is line_empty.script.lua.
function data()
	return {
		type = "notification",
		data = {
			guiType = "Problem",
			label = _("Line Without Vehicles"),
			initiallyIgnoredType = false,
		},
	}
end
