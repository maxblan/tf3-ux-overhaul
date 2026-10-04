---@meta
-- api.engine, typed after apidef/api/engine.d.tl. Only what this repository uses.

---@alias Engine.Entity integer

---Keeps track of modifications to entities.
---@class Engine.Revision
---@field num [integer, integer, integer]

-- Components ----------------------------------------------------------------------------------------

---@class Engine.Component.BaseEdge
---@field type BaseEdgeType
---@field typeIndex integer
---@field laneConfigs LaneConfig[]
---@field node0 Engine.Entity
---@field node1 Engine.Entity
---@field position0 Vec3f
---@field position1 Vec3f
---@field tangent0 Vec3f
---@field tangent1 Vec3f
---@field roadType RoadType
---@field roadTemplate ResName
---@field roadStyle ResName

---@class Engine.Component.BaseNode
---@field position Vec3f

---@class Engine.Component.Carriage
---@field reversed boolean

---@class Engine.Component.Construction
---@field stations Engine.Entity[]

---The internal state of a single game script.
---@class Engine.Component.GameScript
---@field gameScript ResName
---@field state_native NativeLuaTable

---@class Engine.Component.GameSpeed
---@field speedup integer
---@field millisPerDay integer

---@class Engine.Component.GameTime
---@field gameTime integer

---@class Engine.Component.Industry
---@field stockList Engine.Entity
---@field level integer
---@field closureTimeStamp integer
---@field manualDevelopment boolean
---@field maxLevel integer

---How a line stop loads and waits (members not read here).
---@class Engine.Component.Line.LoadMode

---@class Engine.Component.Line.StopConfig
---Index cargo type id + 1: whether to load it.
---@field load boolean[]

---@class Engine.Component.Line.Stop
---@field stationGroup Engine.Entity
---Zero-based station index in the station group.
---@field station integer
---Zero-based terminal index in the station.
---@field terminal integer
---@field alternativeTerminals StationTerminal[]
---@field waypoints Waypoint[]
---@field stopConfig Engine.Component.Line.StopConfig

---@class Engine.Component.Line
---@field stops Engine.Component.Line.Stop[]
---@field customFilters boolean
---@field reservationPriority number
local Line = {}

---@return Engine.Component.Line
---@overload fun(copy: Engine.Component.Line): Engine.Component.Line
function Line.new() end

---@class Engine.Component.PlayerOwned
---@field player Engine.Entity

---@alias Engine.Component.Station Station

---@class Engine.Component.StationGroup
---@field stations Engine.Entity[]

---@class Engine.Component.StockList.Stock
---@field cargoType CargoTypeId

---@class Engine.Component.StockList.Rule
---Per alternative, per stock index: the amount consumed.
---@field input integer[][]
---@field output table<CargoTypeId, integer>
---@field booster boolean

---@class Engine.Component.StockList
---@field stocks Engine.Component.StockList.Stock[]
---@field rules Engine.Component.StockList.Rule[]

---@class Engine.Component.Town
---@field developmentActive boolean

---Modifiers for the whole transport vehicle (userdata).
---@class Engine.Component.TransportVehicle.Modifiers
---@field topSpeedScale number
---@field noiseScale number
---@field pollutionScale number
---@field comfortScale number

---@class Engine.Component.TransportVehicle
---@field carrier Carrier
---@field transportVehicleConfig TransportVehicleConfig
---@field state TransportVehicleState
---@field userStopped boolean
---If in depot, the depot entity.
---@field depot Engine.Entity
---@field sellOnArrival boolean
---The line entity, if assigned to one.
---@field line Engine.Entity
---The zero-based stop index on the line, if assigned to one.
---@field stopIndex integer
---@field noPath boolean

---@class Engine.Component.VehicleDepot
---@field carrier Carrier

---@class Engine.Component.Warehouse
---@field stockList Engine.Entity
---@field construction Engine.Entity

-- Component types -----------------------------------------------------------------------------------
-- Teal types every value as Engine.ComponentType. Here each value has its own subclass, so that
-- getComponent's overloads can pick the component class from the argument.

---@class Engine.ComponentType
---@field BASE_EDGE Engine.ComponentType.BASE_EDGE
---@field BASE_NODE Engine.ComponentType.BASE_NODE
---@field CARRIAGE Engine.ComponentType.CARRIAGE
---@field CONSTRUCTION Engine.ComponentType.CONSTRUCTION
---@field GAME_SCRIPT Engine.ComponentType.GAME_SCRIPT
---@field GAME_SPEED Engine.ComponentType.GAME_SPEED
---@field GAME_TIME Engine.ComponentType.GAME_TIME
---@field INDUSTRY Engine.ComponentType.INDUSTRY
---@field LINE Engine.ComponentType.LINE
---@field PLAYER_OWNED Engine.ComponentType.PLAYER_OWNED
---@field STATION Engine.ComponentType.STATION
---@field STATION_GROUP Engine.ComponentType.STATION_GROUP
---@field STOCK_LIST Engine.ComponentType.STOCK_LIST
---@field TOWN Engine.ComponentType.TOWN
---@field TRANSPORT_VEHICLE Engine.ComponentType.TRANSPORT_VEHICLE
---@field VEHICLE_DEPOT Engine.ComponentType.VEHICLE_DEPOT
---@field WAREHOUSE Engine.ComponentType.WAREHOUSE

---@class Engine.ComponentType.BASE_EDGE: Engine.ComponentType
---@class Engine.ComponentType.BASE_NODE: Engine.ComponentType
---@class Engine.ComponentType.CARRIAGE: Engine.ComponentType
---@class Engine.ComponentType.CONSTRUCTION: Engine.ComponentType
---@class Engine.ComponentType.GAME_SCRIPT: Engine.ComponentType
---@class Engine.ComponentType.GAME_SPEED: Engine.ComponentType
---@class Engine.ComponentType.GAME_TIME: Engine.ComponentType
---@class Engine.ComponentType.INDUSTRY: Engine.ComponentType
---@class Engine.ComponentType.LINE: Engine.ComponentType
---@class Engine.ComponentType.PLAYER_OWNED: Engine.ComponentType
---@class Engine.ComponentType.STATION: Engine.ComponentType
---@class Engine.ComponentType.STATION_GROUP: Engine.ComponentType
---@class Engine.ComponentType.STOCK_LIST: Engine.ComponentType
---@class Engine.ComponentType.TOWN: Engine.ComponentType
---@class Engine.ComponentType.TRANSPORT_VEHICLE: Engine.ComponentType
---@class Engine.ComponentType.VEHICLE_DEPOT: Engine.ComponentType
---@class Engine.ComponentType.WAREHOUSE: Engine.ComponentType

---@class Engine.EntityFilters
---@field requireOwnedByPlayer? Engine.Entity
---@field filterFn? fun(entity: Engine.Entity): boolean

---@class UtilTerrain
---@field isValidCoordinate fun(position: Vec2f): boolean
---@field getHeightAt fun(position: Vec2f): number
---@field getBaseHeightAt fun(position: Vec2f): number
---@field isOnWater fun(position: Vec2f): boolean
---@field getBoundingBox fun(): Box2f

---@class Engine
---@field system System
---@field terrain UtilTerrain
---@field util EngineUtil
local Engine = {}

---The entity's component of the given type, or nil if the entity has none (Teal: a generic
---`getComponent<T>`; the overloads below map each component type to its class).
---@param entity Engine.Entity
---@param componentType Engine.ComponentType.BASE_EDGE
---@return Engine.Component.BaseEdge?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.BASE_NODE): Engine.Component.BaseNode?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.CARRIAGE): Engine.Component.Carriage?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.CONSTRUCTION): Engine.Component.Construction?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.GAME_SCRIPT): Engine.Component.GameScript?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.GAME_SPEED): Engine.Component.GameSpeed?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.GAME_TIME): Engine.Component.GameTime?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.INDUSTRY): Engine.Component.Industry?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.LINE): Engine.Component.Line?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.PLAYER_OWNED): Engine.Component.PlayerOwned?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.STATION): Engine.Component.Station?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.STATION_GROUP): Engine.Component.StationGroup?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.STOCK_LIST): Engine.Component.StockList?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.TOWN): Engine.Component.Town?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.TRANSPORT_VEHICLE): Engine.Component.TransportVehicle?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.VEHICLE_DEPOT): Engine.Component.VehicleDepot?
---@overload fun(entity: Engine.Entity, t: Engine.ComponentType.WAREHOUSE): Engine.Component.Warehouse?
function Engine.getComponent(entity, componentType) end

---@param fn fun(entity: Engine.Entity)
---@param componentType Engine.ComponentType
function Engine.forEachEntityWithComponent(fn, componentType) end

---@param componentType Engine.ComponentType
---@param filters? Engine.EntityFilters
---@return Engine.Entity[]
function Engine.getEntitiesWithComponent(componentType, filters) end

---@param entity Engine.Entity
---@return Engine.Revision
function Engine.getRevision(entity) end

---@param entity Engine.Entity
---@return boolean
function Engine.entityExists(entity) end
