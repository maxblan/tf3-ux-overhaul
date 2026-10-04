---@meta
-- api.engine.util, typed after apidef/api/engine/util.d.tl. Only what this repository uses.

---@class UtilStock
---@field getCargoShippedPerYear fun(stockListEntity: Engine.Entity): integer
---@field getCargoMaxProductionPerYear fun(stockListEntity: Engine.Entity, cargoTypeId: CargoTypeId): integer
---@field getCargoOutputPerYear fun(stockListEntity: Engine.Entity): integer
---@field getProductionRating fun(stockListEntity: Engine.Entity): number
---@field isCargoTypeCurrentlyProduced fun(cargoTypeId: CargoTypeId): boolean

---@class UtilLine.LineCapacityUsage
---@field used number
---@field capacity number

---@class UtilLine.PathProblemLocation
---@field okModes table<TransportMode, boolean>
---@field relaxedModes table<TransportMode, boolean>
---@field allowedModes table<TransportMode, boolean>

---Problems of a line stop.
---@class UtilLine.StopState
---@field noPath boolean
---{flattened terminal index, optional problem location}
---@field noPathFromAlternative [integer, UtilLine.PathProblemLocation?]
---{flattened terminal index, optional problem location}
---@field noPathToAlternative [integer, UtilLine.PathProblemLocation?]
---@field duplicateStop boolean
---@field incompatibleStop boolean
---@field noPathLocation? UtilLine.PathProblemLocation

---@class UtilLine
---Index cargo type id + 1 (an id vector).
---@field getLineCapacityUsages fun(line: Engine.Entity, allCapacities: boolean): UtilLine.LineCapacityUsage[]?
---@field calcLineStationThroughput fun(lineEntity: Engine.Entity): integer
---Per segment between stops, the states of its stops.
---@field getDetailedLineProblems fun(lineEntity: Engine.Entity): UtilLine.StopState[][]
---{line, LineProblem value, optional location of the first problem} for all lines.
---@field getLineProblems fun(): [Engine.Entity, integer, UtilLine.PathProblemLocation?][]
---@field getLineTransportModesUnion fun(lineEntity: Engine.Entity): table<TransportMode, boolean>?
---@field getLinesIssues fun(playerEntity: Engine.Entity, allIssues: boolean): table<Engine.Entity, LineIssue[]>

---@class UtilOctree
---@field findEntitiesInCircle fun(center: Vec2f, radius: number, componentType: Engine.ComponentType): Engine.Entity[]

---@class UtilPathfinding
---Edges of the path as {edge, direction}; empty if there is no path.
---@field findPathNodeToNode fun(from: NodeId[], to: NodeId[], modes: TransportMode[]): [EdgeId, boolean][]

---@class UtilMaintenance
---@field calcMaintenanceForStationGroup fun(stationGroupEntity: Engine.Entity): integer
---@field calcMaintenanceForSubconstruction fun(subconstructionEntity: Engine.Entity): integer

---@class UtilVehicle
---@field getSpeed fun(vehicleEntity: Engine.Entity): number?
---@field getDepreciatedValue fun(vehicleEntity: Engine.Entity): integer
---@field getPartPrice fun(part: TransportVehiclePart): integer

---@class UtilStation.StationGroupCapacityUsage
---@field capacity integer
---@field waitingHallCapacity integer
---@field used integer
---@field overflow boolean

---@class UtilStation
local UtilStation = {}

---@param stationGroup Engine.Entity
---@param flatTerminalIndex integer -1 = the whole group
---@return UtilStation.StationGroupCapacityUsage
function UtilStation.calculateStationGroupCargo(stationGroup, flatTerminalIndex) end

---Userdata: clone() it before keeping it.
---@class UtilCargo.CargoQualityData
---@field clone fun(self: UtilCargo.CargoQualityData): UtilCargo.CargoQualityData
---@field countBad integer
---@field countTotal integer
---@field averageQuality number?
---@field isVeryBad boolean

---@class UtilCargo
local UtilCargo = {}

---@param vehicleEntity Engine.Entity
---@param cargoTypeId? CargoTypeId
---@return UtilCargo.CargoQualityData
function UtilCargo.getCargoQualityDataForVehicle(vehicleEntity, cargoTypeId) end

---@param stationGroupEntity Engine.Entity
---@param cargoTypeId CargoTypeId
---@return UtilCargo.CargoQualityData
function UtilCargo.getCargoQualityDataAtStationGroup(stationGroupEntity, cargoTypeId) end

---@param lineEntity Engine.Entity
---@param stopIndex integer zero-based
---@param cargoTypeId CargoTypeId
---@return UtilCargo.CargoQualityData
function UtilCargo.getCargoQualityDataAtStop(lineEntity, stopIndex, cargoTypeId) end

---@class UtilFinance
---@field calculateEarnings fun(playerEntity: Engine.Entity): integer
---@field computeFinanceTable fun(playerEntity: Engine.Entity, config: ChartConfig): FinanceData
---The balance, or nil when money is infinite.
---@field getPlayersBalance fun(playerEntity: Engine.Entity): integer?
local UtilFinance = {}

---Summed balance of the entities (having an account) over [startTime, endTime].
---@param entities Engine.Entity[]
---@param startTime integer
---@param endTime integer
---@param maintenanceIncomeOnly boolean
---@return integer
function UtilFinance.calculateBalance(entities, startTime, endTime, maintenanceIncomeOnly) end

---@class UtilHeadquarters
---@field getCompaniesValue fun(): CompanyValue

---@class EngineUtil
---@field getPlayer fun(): Engine.Entity
---@field getWorld fun(): Engine.Entity
---@field getYear fun(): integer
---The entity's name, or nil.
---@field getEntityName fun(entity: Engine.Entity): string?
---Age between two timestamps at the current game speed, e.g. "6 years".
---@field formatAge fun(time0: integer, time1: integer): string
---@field cargo UtilCargo
---@field finance UtilFinance
---@field headquarters UtilHeadquarters
---@field line UtilLine
---@field maintenance UtilMaintenance
---@field octree UtilOctree
---@field pathfinding UtilPathfinding
---@field station UtilStation
---@field stock UtilStock
---@field vehicle UtilVehicle
