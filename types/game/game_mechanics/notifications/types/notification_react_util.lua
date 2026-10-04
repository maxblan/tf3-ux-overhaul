---@meta

---@class game.game_mechanics.notifications.types.notification_react_util.NotificationSimpleIconParam: react.Param
---@field icon string
---@field status? game.game_mechanics.notifications.notifications.NotificationGuiData.Status
---@field type game.game_mechanics.notifications.notifications.NotificationGuiData.Type

---@class game.game_mechanics.notifications.types.notification_react_util.NotificationProgressIconParam: game.game_mechanics.notifications.types.notification_react_util.NotificationSimpleIconParam
---@field percentage number

---@class game.game_mechanics.notifications.types.notification_react_util.NotificationProgressData: react.Param
---@field description string
---@field icon string
---@field status? game.game_mechanics.notifications.notifications.NotificationGuiData.Status
---@field type game.game_mechanics.notifications.notifications.NotificationGuiData.Type
---@field progress? game.game_mechanics.notifications.notifications.NotificationGuiData.Progress
---@field progresses? game.game_mechanics.notifications.notifications.NotificationGuiData.Progress[]

---@class game.game_mechanics.notifications.types.notification_react_util
---@field NotificationSimpleIcon react.Recipe<game.game_mechanics.notifications.types.notification_react_util.NotificationSimpleIconParam>
---@field NotificationProgressIcon react.Recipe<game.game_mechanics.notifications.types.notification_react_util.NotificationProgressIconParam>
---@field NotificationProgressContent react.Recipe<game.game_mechanics.notifications.types.notification_react_util.NotificationProgressData>
local M = {}

return M
