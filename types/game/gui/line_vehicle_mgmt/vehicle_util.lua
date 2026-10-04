---@meta

---@class game.gui.line_vehicle_mgmt.vehicle_util.AgeInfo
---@field age string
---@field purchaseTime integer
---@field agePercent number
---@field timeRemaining string?

---@class game.gui.line_vehicle_mgmt.vehicle_util
local M = {}

---{ earliest purchase time, shortest lifespan } of the vehicle's parts.
---@param transportVehicle Engine.Component.TransportVehicle
---@return [integer, integer]
function M.getMinPurchaseTimeAndLifespan(transportVehicle) end

---@param condition number
---@return string
function M.getConditionText(condition) end

---@param condition number
---@return string
function M.getConditionIcon(condition) end

---Average maintenance state (1 without parts) and average maintenance change of the parts.
---@param vehicleEntity Engine.Entity
---@return number state
---@return number change
function M.getAvgMaintenanceState(vehicleEntity) end

---@param vehicleEntity Engine.Entity
---@return game.gui.line_vehicle_mgmt.vehicle_util.AgeInfo
function M.getAge(vehicleEntity) end

---@param vehicleEntity Engine.Entity
---@return integer[]
function M.GetVehicleModelIds(vehicleEntity) end

---{ rating text, tooltip, rating } of the vehicle's power, nil if it has none.
---@param weight number
---@param power number
---@param tractiveEffort number
---@param topSpeed number
---@param rollingFriction number
---@return [string, string, number]?
function M.getPowerRatingTextAndToolTip(weight, power, tractiveEffort, topSpeed, rollingFriction) end

return M
