--- Notification type "Line without vehicles" (GUI side). Sent by gui/notifications.lua.
local common = require("/ux_overhaul/notifications/common.lua")

local line_empty = {}

function line_empty.useDataState(params)
	return common.use_entity_state(params, function(line)
		return { name = api.engine.util.getEntityName(line) or "" }
	end, function(d)
		return {
			title = _("Line Without Vehicles"),
			description = string.format(_("%s has no vehicles. It transports nothing."), d.name),
			tooltip = _("Line Without Vehicles"),
			icon = common.ICONS.line_empty,
		}
	end)
end

function data()
	return line_empty
end

return line_empty
