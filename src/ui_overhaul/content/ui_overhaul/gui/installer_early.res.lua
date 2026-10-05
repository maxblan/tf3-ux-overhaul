-- Installs the features before every other mod's replacement config (installer.lua).
---@return table
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "ui_overhaul_1::/ui_overhaul/gui/installer.script",
			doReplaceFn = "early",
			order = -1000000000,
		},
	}
end
