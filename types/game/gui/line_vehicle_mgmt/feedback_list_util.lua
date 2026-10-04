---@meta

---@alias game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackDialogParam.SoundOnAccept "SellVehicle"|"DeleteLine"

---A question with an accept button in the feedback list.
---@class game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackDialogParam
---@field onAccept fun()
---@field acceptText string
---@field soundOnAccept? game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackDialogParam.SoundOnAccept

---@alias game.gui.line_vehicle_mgmt.feedback_list_util.Mode "Info"|"Warning"|"Error"|"Question"

---Api of FeedbackList nodes.
---@class game.gui.line_vehicle_mgmt.feedback_list_util.FeedBackViewerAPI
---@field addFeedback fun(message: string, mode?: string, dialogData?: game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackDialogParam, timeout?: number, id?: number, dismissible?: boolean)
---@field hasFeedback fun(): boolean

---@class game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackListParams: react.Param

---@class game.gui.line_vehicle_mgmt.feedback_list_util
---@field FeedbackList react.RecipeWithApi<game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackListParams, game.gui.line_vehicle_mgmt.feedback_list_util.FeedBackViewerAPI>
local M = {}

return M
