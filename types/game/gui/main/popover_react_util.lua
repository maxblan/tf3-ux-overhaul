---@meta

---@class game.gui.main.popover_react_util.PopoverWindowParam: react.Param
---@field onClose fun()
---@field windowClass? string
---@field windowTitle? string
---@field x? number
---@field y? number
---@field recipe react.Recipe<any> the content recipe, called with `params`
---@field params any the param of `recipe`
---@field compact? boolean

---@class game.gui.main.popover_react_util
---@field PopoverWindowContent react.Recipe<game.gui.main.popover_react_util.PopoverWindowParam>
---@field PopoverWindow react.Recipe<game.gui.main.popover_react_util.PopoverWindowParam>
local M = {}

return M
