-- Decides, after every other mod's replacement config, which mod wins where both change the same part
-- of the UI: the one that comes first in the mod list (installer.lua, priority.lua).
---@return table
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "ui_overhaul_1::/ui_overhaul/gui/installer.script",
			doReplaceFn = "late",
			order = 1000000000,
		},
	}
end
