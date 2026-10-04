---@meta

---@class game.gui.line_vehicle_mgmt.line_react_util.NameTextViewParams: react.Param
---@field entity Engine.Entity
---@field locationButton? boolean
---@field stackEntityOpen? boolean
---@field nameEntity? Engine.Entity
---@field onClickOverride? fun(entity: Engine.Entity)
---@field editMode? boolean
---@field tooltip? string
---@field styleClass? string
---@field maxLength? integer

---@class game.gui.line_vehicle_mgmt.line_react_util.ColorWidgetParam: react.Param
---@field entity Engine.Entity
---@field color? Vec3f
---@field tooltip? string
---@field onClick? fun()

---@class game.gui.line_vehicle_mgmt.line_react_util.LineBalanceParams: react.Param
---@field entity Engine.Entity
---@field stepTimer? boolean

---@class game.gui.line_vehicle_mgmt.line_react_util
---@field ManagerNotificationWidget react.Recipe<Engine.Entity>
---@field VehicleInstructionsIcon react.Recipe<Engine.Entity>
---@field VehicleInstructionsName react.Recipe2<Engine.Entity, boolean> vehicle, withLocation
---@field ColorWidget react.Recipe<game.gui.line_vehicle_mgmt.line_react_util.ColorWidgetParam>
---@field NameTextView react.Recipe<game.gui.line_vehicle_mgmt.line_react_util.NameTextViewParams>
---@field LineBalance react.Recipe<game.gui.line_vehicle_mgmt.line_react_util.LineBalanceParams>
local M = {}

---@param text string
---@return react.TreeNodeId
function M.makeTooltip(text) end

---@param terminalNumber integer
---@param slim boolean
---@param labelOverride? string
---@return react.TreeNodeId
function M.makeTerminalIndicator(terminalNumber, slim, labelOverride) end

return M
