---@meta

---@class game.gui.main.gui_react_util.ClipperParam: react.Param
---@field layout react.TreeNodeId

---@alias game.gui.main.gui_react_util.EmoteIconParam.Satisfaction "Happy"|"Aloof"|"Sad"

---@class game.gui.main.gui_react_util.EmoteIconParam: react.Param
---@field satisfaction game.gui.main.gui_react_util.EmoteIconParam.Satisfaction
---@field tooltip? string
---@field forceFocusable? boolean

---@class game.gui.main.gui_react_util.FocusTraversalScopeParam: react.Param
---@field horizontal? boolean
---@field vertical? boolean
---@field allowBubbleUp? boolean let ancestors handle the input action at the end (default false)
---@field layout react.TreeNodeId

---@class game.gui.main.gui_react_util
---@field Clipper react.Recipe<game.gui.main.gui_react_util.ClipperParam>
---@field EmoteIcon react.Recipe<game.gui.main.gui_react_util.EmoteIconParam>
---@field FocusTraversalScope react.Recipe<game.gui.main.gui_react_util.FocusTraversalScopeParam>
local M = {}

---@param value integer
---@param tag? string
---@return react.TreeNodeId
function M.integer2TextLayout(value, tag) end

---@return react.TreeNodeId
function M.makeHorizontalSpacer() end

---@return react.TreeNodeId
function M.makeVerticalSpacer() end

---Text colour readable on `color`.
---@param color Vec4f
---@return Vec4f
function M.textColorForColor(color) end

return M
