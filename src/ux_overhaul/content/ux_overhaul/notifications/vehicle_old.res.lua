-- Notification type of UX Overhaul; the GUI side is vehicle_old.script.lua.
function data()
	return {
		type = "notification",
		data = {
			guiType = "Caution",
			label = _("Vehicle Past Its Lifespan"),
			initiallyIgnoredType = false,
		},
	}
end
