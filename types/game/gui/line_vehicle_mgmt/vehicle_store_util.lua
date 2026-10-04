---@meta

---A vehicle model as the vehicle store lists it (VehicleStoreUtil.Vehicle); passed on unchanged.
---@class game.gui.line_vehicle_mgmt.vehicle_store_util.Vehicle
---@field length number
---@field maintenanceState number

---Data of a consist (VehicleStoreUtil.VehicleData), the fields this repo uses.
---@class game.gui.line_vehicle_mgmt.vehicle_store_util.VehicleData
---@field speed number
---@field weight number
---@field weightMaxPayload number
---@field tractiveEffort number
---@field rollingFriction number
---@field power number

---@class game.gui.line_vehicle_mgmt.vehicle_store_util
local M = {}

---@param model Model
---@return game.gui.line_vehicle_mgmt.vehicle_store_util.Vehicle
function M.makeSingleVehicle(model) end

---@param vehicles game.gui.line_vehicle_mgmt.vehicle_store_util.Vehicle[]
---@param modifiers? Engine.Component.TransportVehicle.Modifiers
---@return game.gui.line_vehicle_mgmt.vehicle_store_util.VehicleData
function M.collectVehicleData(vehicles, modifiers) end

return M
