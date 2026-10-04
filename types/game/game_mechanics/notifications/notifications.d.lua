---@meta
-- Types of game_mechanics/notifications/notifications.d.tl (no module of its own here).

---@alias game.game_mechanics.notifications.notifications.NotificationGuiData.Type
---| "Info"
---| "Caution"
---| "Problem"
---| "Opportunity"
---| "Achievement"
---| "Unknown"

---@alias game.game_mechanics.notifications.notifications.NotificationGuiData.Status "Pending"|"Failed"

---@class game.game_mechanics.notifications.notifications.NotificationGuiData.Progress
---@field percentage number
---@field text string
---@field remainingDurationMs? number

---What a notification type's useDataState returns.
---@class game.game_mechanics.notifications.notifications.NotificationGuiData
---@field title string
---@field description string
---@field icon string
---@field hudIcon? string
---@field lvmIcon? string
---@field iconExplainTooltip? string
---@field previewImage? string
---@field wouldClick? fun(): boolean
---@field onClick? fun(stack: boolean, dryRun?: boolean): boolean
---@field status? game.game_mechanics.notifications.notifications.NotificationGuiData.Status
---@field progress? game.game_mechanics.notifications.notifications.NotificationGuiData.Progress
---@field progresses? game.game_mechanics.notifications.notifications.NotificationGuiData.Progress[]
---@field soundOnMount? FilePath[] one of them plays at random

---@class game.game_mechanics.notifications.notifications.Notification
---@field type string
---@field params table<string, any> the notification type's own params
---@field notificationId integer
---@field autoDismissDuration? integer
---@field simParams any the notification type's own simulation params

---An entry of the notification history (NotificationsState.Entry).
---@class game.game_mechanics.notifications.notifications.NotificationsState.Entry
---@field timestamp integer
---@field notification game.game_mechanics.notifications.notifications.Notification
---@field persisting? game.scripts.entity_util.EntityAndRevision[] if not empty, kept with the history entry
---@field dismissed? boolean
---@field expired? boolean
---@field tracked? boolean
---@field playedInitialSound? boolean
