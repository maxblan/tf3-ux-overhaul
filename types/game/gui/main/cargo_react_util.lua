---@meta

---@class game.gui.main.cargo_react_util
local M = {}

---@param cargoTypeId CargoTypeId
---@param class? string
---@param iconOverride? string
---@param withoutTooltip? boolean
---@param forceFocusable? boolean
---@param tooltipModifier? fun(tooltip: string): string
---@return react.TreeNodeId
function M.makeCargoIcon(cargoTypeId, class, iconOverride, withoutTooltip, forceFocusable, tooltipModifier) end

return M
