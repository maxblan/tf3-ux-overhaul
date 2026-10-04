---@meta

---@alias game.gui.statistics.statistics_react_util.StationGroupType "Passenger"|"Cargo"|"Mixed"

---@class game.gui.statistics.statistics_react_util.CargoColumnData
---@field supply integer
---@field demand integer
---@field coverage number
---@field averageQuality number

---@class game.gui.statistics.statistics_react_util
---@field ProblemsCell react.Recipe<builtin.TableCellParam>
local M = {}

---@param vehicleEntity Engine.Entity
---@return game.gui.statistics.statistics_react_util.CargoColumnData
function M.calculateCargoColumnDataForVehicle(vehicleEntity) end

---@param lineEntity Engine.Entity
---@return game.gui.statistics.statistics_react_util.CargoColumnData
function M.calculateCargoColumnDataForLine(lineEntity) end

---@param entity Engine.Entity station group
---@return game.gui.statistics.statistics_react_util.StationGroupType?
function M.getStationGroupType(entity) end

---@return react.TreeNodeId
function M.createFocusDummyForGamepad() end

---Sort key with the number of notifications most significant: { count, notification ids }.
---@param notificationsState table<Engine.Entity, integer[]>
---@param entity Engine.Entity
---@return [integer, integer[]]
function M.getProblemsCompareValue(notificationsState, entity) end

---Carriers of the active categories; nil if none is active or an active one has no carrier (all).
---@param allCategories game.gui.statistics.statistics.StatisticsRecipeParams.Category[]
---@param activeCategories table<integer, boolean>
---@return Carrier[]?
function M.getCarrierFilterFromCategories(allCategories, activeCategories) end

return M
