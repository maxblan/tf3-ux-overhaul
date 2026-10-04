---@meta

---@class game.game_mechanics.notifications.notification_util
local M = {}

---The notifications game script's state, as a native table.
---@return NativeLuaTable
function M.externalGetNotificationsStateNative() end

---@param nativeState NativeLuaTable
---@return table<Engine.Entity, integer[]> notification ids per persisting entity
function M.getPersistingEntity2NotificationFromNative(nativeState) end

---Notification ids, oldest first.
---@param nativeState NativeLuaTable
---@return integer[]
function M.getHistoryFromNative(nativeState) end

---@param nativeState NativeLuaTable
---@param notificationId integer
---@return game.game_mechanics.notifications.notifications.Notification
function M.getNotificationFromNative(nativeState, notificationId) end

---@param nativeState NativeLuaTable
---@param notificationId integer
---@return game.game_mechanics.notifications.notifications.NotificationsState.Entry
function M.getNotificationEntryFromNative(nativeState, notificationId) end

---"Unknown" when the type's resource does not exist.
---@param name string notification type (script or res name)
---@return game.game_mechanics.notifications.notifications.NotificationGuiData.Type
function M.getGuiTypeFromNotificationType(name) end

return M
