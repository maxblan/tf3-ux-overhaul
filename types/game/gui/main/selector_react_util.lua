---@meta

---@class game.gui.main.selector_react_util.DefaultSelectorCompParams: react.Param
---@field refRC react.RefWrapApi<builtin.RenderComponentAPI>
---@field inspectorMode? boolean
---@field gameCtx game.gui.main.game_context.GameContext
---@field invertedSelectionColors? boolean

---@class game.gui.main.selector_react_util
local M = {}

---The map's default action function (selection, tooltips, layer).
---@param params game.gui.main.selector_react_util.DefaultSelectorCompParams
---@return fun(): react.TreeNodeId
function M.makeDefaultSelectorCombinedFn(params) end

return M
