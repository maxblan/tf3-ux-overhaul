---@meta

---@class game.gui.line_vehicle_mgmt.vehicle_list_react_util.VehicleListParams: react.Param
---@field vehicles Engine.Entity[]
---@field managerRef react.RefWrapApi<game.gui.line_vehicle_mgmt.manager_window.VehicleManagerApi>
---@field managerActionButtonsRef react.RefWrap
---@field commonParams game.gui.line_vehicle_mgmt.line_util.CommonActionParams
---@field onClickSelectLineOrDepot fun(entity: Engine.Entity, isLine: boolean)
---@field onClickSelectVehicle fun(vehicleEntity: Engine.Entity)

---@class game.gui.line_vehicle_mgmt.vehicle_list_react_util
---@field VehicleList react.Recipe<game.gui.line_vehicle_mgmt.vehicle_list_react_util.VehicleListParams>
local M = {}

return M
