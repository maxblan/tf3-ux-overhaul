--- Notification type "Line loses money" (GUI side). Sent by gui/notifications.lua.
local common = require("/ux_overhaul/notifications/common.lua")

local line_losing = {}

function line_losing.useDataState(params)
	return common.use_entity_state(params, function(line)
		return { name = api.engine.util.getEntityName(line) or "", balance = common.balance_12_months(line) }
	end, function(d)
		return {
			title = _("Line Loses Money"),
			description = string.format(_("%s lost %s in the last 12 months."), d.name, api.util.formatMoney(-d.balance)),
			tooltip = _("Line Loses Money"),
			icon = common.ICONS.line,
		}
	end)
end

function data()
	return line_losing
end

return line_losing
