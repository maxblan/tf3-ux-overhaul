---@meta

---@alias game.gui.main.cargo_util.CargoListSortOrder "CAPACITY"|"COUNT"|"ID"

---A stock of an industry, warehouse or station.
---@class game.gui.main.cargo_util.StockConfig
---@field ids StockId[]
---@field stored integer
---@field capacity integer
---@field cargoTypesSorted CargoTypeId[]
---@field allCargoTypes boolean
---@field tendency integer
---@field stockType StockListType
---@field quality integer
---@field numSpoiled integer
---@field canPinCargoType boolean
---@field pinnedCargoType boolean

---@class game.gui.main.cargo_util.StockCargoCount
---@field cargoType CargoTypeId
---@field count integer
---@field spoiledCount integer
---@field tendency integer
---@field quality number

---@class game.gui.main.cargo_util.VehicleCargo
---@field cargoType CargoTypeId
---@field capacity integer
---@field vehicleEntities Engine.Entity[]
---@field fill integer
---@field hasGoodCargo boolean
---@field hasBadCargo boolean

---What to list cargo of: a vehicle, a stock list owner or a line (stop).
---@class game.gui.main.cargo_util.CargoLocationParams
---@field vehicleEntity? Engine.Entity
---@field stockListOwnerEntity? Engine.Entity
---@field lineEntity? Engine.Entity
---@field stopIndex1? integer
---@field getTendency? boolean
---@field showEmpty? boolean
---@field extraCapacity? table<CargoTypeId, integer>

---@class game.gui.main.cargo_util.CargoStopParams
---@field lineEntity Engine.Entity
---@field stopIndex1 integer
---@field getTendency? boolean
---@field showEmpty? boolean

---@class game.gui.main.cargo_util.CargoTypeInfo
---@field cargoType CargoTypeId
---@field cargoTypes CargoTypeId[]
---@field capacity integer
---@field count integer
---@field tendency integer
---@field spoiledCount integer
---@field averageQuality number

---@class game.gui.main.cargo_util.VehicleUnsetCapacities
---@field multiTypes game.gui.main.cargo_util.CargoTypeInfo[]
---@field singleCapacities table<CargoTypeId, integer>

---@class game.gui.main.cargo_util
local M = {}

---@return CargoTypeId
function M.getPassengerCargoTypeId() end

---Stocks of `entity`, their number, and whether there were more than `max`.
---@param entity Engine.Entity
---@param max? integer
---@param calculateQuality? boolean
---@param sortByType? boolean
---@param showEmpty? boolean
---@param groupStocks? boolean
---@param producedOnly? boolean
---@return game.gui.main.cargo_util.StockConfig[]
---@return integer
---@return boolean
function M.calculateStockConfigs(entity, max, calculateQuality, sortByType, showEmpty, groupStocks, producedOnly) end

---@param entity Engine.Entity holder of the stocks (industry, warehouse ...)
---@param sortByCargoType? boolean by cargo type instead of count
---@param stockIds? StockId[] only these stocks of `entity`
---@param calculateQuality? boolean
---@return game.gui.main.cargo_util.StockCargoCount[]
function M.calculateStockCargoCount(entity, sortByCargoType, stockIds, calculateQuality) end

---@param vehicleEntity Engine.Entity
---@param calculateQuality? boolean
---@return game.gui.main.cargo_util.VehicleCargo[]
function M.calculateSortedVehicleCargoInfo(vehicleEntity, calculateQuality) end

---Sort key with the cargo type most significant.
---@param vehicleEntity Engine.Entity
---@return [CargoTypeId, integer, integer][]
function M.calculateSortedVehicleCargoInfoCompareValue(vehicleEntity) end

---@param lineEntity Engine.Entity
---@param calculateQuality? boolean
---@return game.gui.main.cargo_util.VehicleCargo[]
function M.calculateSortedLineCargoInfo(lineEntity, calculateQuality) end

---Sort key with the cargo type most significant.
---@param lineEntity Engine.Entity
---@return [CargoTypeId, integer, integer][]
function M.calculateSortedLineCargoInfoCompareValue(lineEntity) end

---@param locationParams game.gui.main.cargo_util.CargoLocationParams
---@param sortOrder game.gui.main.cargo_util.CargoListSortOrder
---@param passengersFirst? boolean
---@param cargoTypeFilter? fun(cargoTypeId: CargoTypeId): boolean
---@param allLineCapacities? boolean
---@return CargoTypeId[]
function M.getSortedProducedCargoTypes(locationParams, sortOrder, passengersFirst, cargoTypeFilter, allLineCapacities) end

---@param stopParams game.gui.main.cargo_util.CargoStopParams
---@param passengersFirst? boolean
---@return CargoTypeId[]
function M.getConfiguredStopCargoTypes(stopParams, passengersFirst) end

---@return string
function M.getMixedCargoIcon() end

---@param cargoTypeId CargoTypeId
---@return string
function M.getCargoNameById(cargoTypeId) end

---@param vehicleEntity Engine.Entity
---@return game.gui.main.cargo_util.VehicleUnsetCapacities
function M.getVehicleUnsetCapacities(vehicleEntity) end

return M
