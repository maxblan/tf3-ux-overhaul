---@meta
-- api.engine.system, typed after apidef/api/engine/system.d.tl. Only what this repository uses.

---@class LineSystem
---@field getLinesForPlayer fun(playerEntity: Engine.Entity): Engine.Entity[]
---{line entity, zero-based stop index} per line stop at the station.
---@field getLineStopsForStation fun(stationEntity: Engine.Entity): [Engine.Entity, integer][]
---@field getLinesForStationGroup fun(stationGroup: Engine.Entity): Engine.Entity[]

---@class StationSystem
---@field getTown fun(stationEntity: Engine.Entity): Engine.Entity

---@class StationGroupSystem
---@field getStationGroup fun(stationEntity: Engine.Entity): Engine.Entity
local StationGroupSystem = {}

---{carriers, transport modes} of a terminal. station -1 (then terminal -1) = all terminals.
---@param stationGroup Engine.Entity
---@param station integer zero-based
---@param terminal integer zero-based
---@return [Carrier[], TransportMode[]]?
function StationGroupSystem.getCarriers(stationGroup, station, terminal) end

---@class GameScriptSystem
---@field getEntityForGameScript fun(name: string): Engine.Entity?

---@class CarriageListSystem.CarriageInfo
---@field owningVehicle Engine.Entity
---@field index integer

---@class CarriageListSystem
---@field getVehicleInfo fun(vehicleEntity: Engine.Entity): CarriageListSystem.CarriageInfo?

---@class TransportVehicleSystem
---@field getLineVehicles fun(lineEntity: Engine.Entity): Engine.Entity[]
local TransportVehicleSystem = {}

---Terminals of the stop that are too short for the line's vehicles.
---@param lineEntity Engine.Entity
---@param stopIndex number
---@return table<StationTerminal, boolean>
function TransportVehicleSystem.checkLineStopForVehicleOverlength(lineEntity, stopIndex) end

---@class LandVehicleMoveSystem
---@field isTrainWaitingForFreePath fun(trainEntity: Engine.Entity): boolean?

---@class CatchmentAreaSystem
---Entities holding a StockList (cargo) or PersonCapacity component in reach of the station.
---@field getStationCatchables fun(stationEntity: Engine.Entity, cargo: boolean): Engine.Entity[]

---@class StreetConnectorSystem
---@field getConstructionEntityForStation fun(stationEntity: Engine.Entity): Engine.Entity

---@class System
---@field carriageListSystem CarriageListSystem
---@field catchmentAreaSystem CatchmentAreaSystem
---@field gameScriptSystem GameScriptSystem
---@field landVehicleMoveSystem LandVehicleMoveSystem
---@field lineSystem LineSystem
---@field stationSystem StationSystem
---@field stationGroupSystem StationGroupSystem
---@field streetConnectorSystem StreetConnectorSystem
---@field transportVehicleSystem TransportVehicleSystem
