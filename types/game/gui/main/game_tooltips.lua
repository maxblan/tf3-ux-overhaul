---@meta

---@class game.gui.main.game_tooltips.DefaultEntityTooltipParam: react.Param
---@field entityRef react.Ref<Engine.Entity>
---@field filter? fun(entity: Engine.Entity): boolean

---@class game.gui.main.game_tooltips
---@field DefaultEntityToolTip react.Recipe<game.gui.main.game_tooltips.DefaultEntityTooltipParam>
local M = {}

return M
