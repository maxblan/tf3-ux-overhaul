--- Shared GUI side of the mod's notification types (*.script.lua next to this file). useDataState is
-- a hook: it polls with useStepStateTimer, whose callback must only read the engine (no translation).
-- @module ux_overhaul.notifications.common
local entity_util = require("::/scripts/entity_util.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local notification_util = require("::/game_mechanics/notifications/notification_util.tl")

local common = {}

common.ICONS = {
	line = "::/game_mechanics/notifications/gui/icons/line_minus.tga",
	line_empty = "::/game_mechanics/notifications/gui/icons/line_minus_x.tga",
	vehicle = "::/game_mechanics/notifications/gui/icons/relation_bus_repair.tga",
}

local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

function common.balance_12_months(entity)
	local t = now()
	local from = math.max(t - api.util.getDefaultYearDuration(), 0)
	return api.engine.util.finance.calculateBalance({ entity }, from, t, true)
end

--- useDataState for a notification about one entity. `read(entity)` returns plain data (engine reads
-- only) or nil; `describe(data)` builds { title, description, tooltip, icon, hud } in render.
function common.use_entity_state(params, read, describe)
	local state = engine_react_util.useStepStateTimer(function()
		if not params or not params.entity or entity_util.entityChanged0(params.entity) then return nil end
		return read(params.entity.entity)
	end, 2.0)
	local data = state:old()
	if not data then return nil end
	local text = describe(data)
	return {
		title = text.title,
		description = text.description,
		icon = text.icon,
		hudIcon = text.hud and text.icon or nil,
		lvmIcon = text.icon,
		iconExplainTooltip = text.tooltip,
		wouldClick = notification_util.makeDefaultWouldClick({ params.entity }),
		onClick = notification_util.makeDefaultOnClick({ params.entity }),
	}
end

return common
