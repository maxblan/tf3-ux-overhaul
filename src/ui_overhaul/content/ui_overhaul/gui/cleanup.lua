--- One-time cleanup for savegames that contain notifications of the old "ux_overhaul" types, which
-- the mod no longer has. Ends any persistent notifications of those types, so the log does not keep
-- entries whose type does not exist. Runs from the entry point's per-frame step.
-- @module ui_overhaul.gui.cleanup
local notification_util = require("::/game_mechanics/notifications/notification_util.tl")

local cleanup = {}

local OLD_TYPES = {
	"ux_overhaul_1::/ux_overhaul/notifications/line_losing.script",
	"ux_overhaul_1::/ux_overhaul/notifications/line_empty.script",
	"ux_overhaul_1::/ux_overhaul/notifications/vehicle_old.script",
}
local RUN_AT_STEP = 120

local steps = 0

local function has_old_entries()
	local native = notification_util.externalGetNotificationsStateNative()
	if not native then return false end
	for _e, ids in pairs(notification_util.getPersistingEntity2NotificationFromNative(native)) do
		for _i, id in ipairs(ids) do
			local n = notification_util.getNotificationFromNative(native, id)
			if n and n.type and n.type:find("ux_overhaul/notifications/", 1, true) then return true end
		end
	end
	return false
end

local function run()
	if not has_old_entries() then return end
	for _i, name in ipairs(OLD_TYPES) do
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", "updatePersistent",
			{ type = name, entitiesAndParam = {}, passOnlyParam = true }))
	end
	debugPrint("[ui_overhaul] removed notifications of an earlier development build")
end

--- Called every step by the entry point.
function cleanup.step()
	steps = steps + 1
	if steps ~= RUN_AT_STEP then return end
	local ok, err = pcall(run)
	if not ok then debugPrint("[ui_overhaul] notification cleanup failed: ", tostring(err)) end
end

return cleanup
