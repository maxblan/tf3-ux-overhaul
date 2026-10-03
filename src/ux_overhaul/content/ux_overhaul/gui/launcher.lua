--- Quick-launch buttons next to the layer buttons (backlog A2): windows that have no hotkey or sit
-- deep in menus, one click each.
-- Rendered by the guarded stub launcher.script.lua.
-- @module ux_overhaul.gui.launcher
local actions = require("/ux_overhaul/gui/actions.lua")
local ui = require("/ux_overhaul/gui/ui.lua")

local launcher = {}

--- Plugin body for ::MainModButtonAreaExtension.
function launcher.render()
	return ui.row({
		ui.button({ ui.icon(ui.ICONS.alert) }, function() actions.open_control_center() end,
			{ id = "uxo.launcher.control_center", tooltip = _("Control Center: problems and lines at a glance") }),
		ui.button({ ui.icon(ui.ICONS.money) }, function() actions.open_finances("Overview") end,
			{ id = "uxo.launcher.finances", tooltip = _("Finances") }),
		ui.button({ ui.icon(ui.ICONS.save) }, function() actions.save_game() end,
			{ id = "uxo.launcher.save", tooltip = _("Save the game under its current name") }),
	})
end

return launcher
