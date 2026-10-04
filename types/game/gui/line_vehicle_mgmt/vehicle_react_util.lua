---@meta

---@class game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleWidgetParams: react.Param
---@field vehicleEntities Engine.Entity[]
---@field onClick? fun()
---@field class? string
---@field blinking? boolean
---@field tooltipOverride? string

---@class game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleBalanceParams: react.Param
---@field entity Engine.Entity
---@field stepTimer? boolean

---A vehicle to buy (vehicleEntity < 0), replace or sell (no parts).
---@class game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleChange
---@field vehicleEntity Engine.Entity
---@field config TransportVehicleConfig

---@class game.gui.line_vehicle_mgmt.vehicle_react_util
---@field VehicleWidget react.Recipe<game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleWidgetParams>
---@field VehicleBalance react.Recipe<game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleBalanceParams>
local M = {}

---Buys, replaces or sells the vehicles. The callbacks are only used for new vehicles.
---@param changes game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleChange[]
---@param protectedEntities? table<Engine.Entity, game.gui.main.game_context.GameContext.Filters.ProtectionConfig|boolean>
---@param getLineAndDepot? fun(vehicleEntity: Engine.Entity): [Engine.Entity, Engine.Entity] needed for new vehicles
---@param getFirstStopToSendTo? fun(vehicleToSendToLine: Engine.Entity, lineToSendTo: Engine.Entity): integer
---@param onBuy? fun(resultEntities: [Engine.Entity, Engine.Revision][])
---@param onFail? fun(reason: string)
function M.HandleVehicleChanges(changes, protectedEntities, getLineAndDepot, getFirstStopToSendTo, onBuy, onFail) end

return M
