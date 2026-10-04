---@meta

---@alias game.gui.main.script_param_util.ParamForUi.IconStyle "Default"|"Colored"

---A script parameter as the GUI shows it (ScriptParamUtil.ParamForUi).
---@class game.gui.main.script_param_util.ParamForUi
---@field uiType ScriptParamType
---@field iconStyle? game.gui.main.script_param_util.ParamForUi.IconStyle
---@field name string
---@field values? string[]
---@field numbers? number[]
---@field tooltips? string[]
---@field defaultIndex? integer buildScriptParamCompSimple does not read it
---@field hideLabel? boolean
---@field allowCoalesce? boolean delay onValueChange, e.g. to the mouse release of a slider
---@field makeCompactButtonFn? fun(value: number): react.TreeNodeId
---@field formatValueFn? fun(value: number): string
---@field stepValueFn? fun(value: number, direction: integer, precise: boolean): number

---@class game.gui.main.script_param_util.CompSimpleParam: react.Param
---@field scriptParam game.gui.main.script_param_util.ParamForUi
---@field currentValue number
---@field onValueChange fun(value: number)
---@field toggleButtonsFlowLayout? boolean
---@field vertical? boolean
---@field compact? boolean
---@field addSpacer? boolean
---@field disableGamepadNavigation? boolean
---@field onHover? fun(hovered: boolean)
---@field gameCtx? game.gui.main.game_context.GameContext
---@field updateCurrentValue? boolean

---@class game.gui.main.script_param_util
local M = {}

---@param param game.gui.main.script_param_util.CompSimpleParam
---@return react.TreeNodeId
function M.buildScriptParamCompSimple(param) end

---The parameter's label and `node`, in a row (or a column if `vertical`).
---@param text string
---@param vertical boolean
---@param node react.TreeNodeId
---@param addSpacer? boolean
---@param onHover? fun(hovered: boolean)
---@param extraClass? string
---@return react.TreeNodeId
function M.wrap(text, vertical, node, addSpacer, onHover, extraClass) end

return M
