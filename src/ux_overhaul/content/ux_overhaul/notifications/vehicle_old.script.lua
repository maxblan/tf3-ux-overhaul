--- Notification type "Vehicle past its lifespan" (GUI side). Sent by gui/notifications.lua.
local common = require("/ux_overhaul/notifications/common.lua")

local vehicle_old = {}

function vehicle_old.useDataState(params)
	return common.use_entity_state(params, function(vehicle)
		return { name = api.engine.util.getEntityName(vehicle) or "" }
	end, function(d)
		return {
			title = _("Vehicle Past Its Lifespan"),
			description = string.format(
				_("%s has reached the end of its lifespan. Replace it: old vehicles break down and cost more."), d.name),
			tooltip = _("Vehicle Past Its Lifespan"),
			icon = common.ICONS.vehicle,
		}
	end)
end

function data()
	return vehicle_old
end

return vehicle_old
