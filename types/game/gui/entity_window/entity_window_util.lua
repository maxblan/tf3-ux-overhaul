---@meta

---@alias game.gui.entity_window.entity_window_util.ActionBarButton.Sound "Buy"|"SendToDepot"|"Sell"

---A button of an entity window's action bar.
---@class game.gui.entity_window.entity_window_util.ActionBarButton
---@field isSpacer? boolean
---@field icon? string
---@field description? string
---@field onClick? fun()
---@field tag? string
---@field customItem? react.TreeNodeId
---@field sound? game.gui.entity_window.entity_window_util.ActionBarButton.Sound
---@field toggleButton? boolean
---@field onValueChange? fun(value: boolean)
---@field value? boolean

---@class game.gui.entity_window.entity_window_util.ActionButtonBarParams: react.Param
---@field primaryButtons? game.gui.entity_window.entity_window_util.ActionBarButton[]
---@field secondaryButtons? game.gui.entity_window.entity_window_util.ActionBarButton[]
---@field nextUpFocusRef? react.RefWrap

---@class game.gui.entity_window.entity_window_util
---@field ActionButtonBar react.Recipe<game.gui.entity_window.entity_window_util.ActionButtonBarParams>
local M = {}

return M
