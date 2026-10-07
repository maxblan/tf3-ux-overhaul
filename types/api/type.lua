---@meta
-- api.type and the data types of the engine API, typed after apidef/api/type.d.tl (and
-- apidef/api/type/mod.d.tl). Only what this repository uses.

---@alias ResName string
---@alias FilePath string
---@alias CargoTypeId integer
---@alias CargoClassId integer
---@alias StockId integer

-- Native containers ---------------------------------------------------------------------------------

---A C++ vector.
---@class Vector<T>
---@field at fun(self: Vector<T>, i: integer): T 1-based index
---@field size fun(self: Vector<T>): integer

---@alias NativeLuaValue string|number|boolean|nil|NativeLuaTable

---A Lua table kept by the engine.
---@class NativeLuaTable
---@field find fun(self: NativeLuaTable, k: NativeLuaValue): NativeLuaValue

---A task running in the background.
---@class Async<T>
---@field isCompleted fun(self: Async<T>): boolean
---Blocks until the task is complete and returns its result.
---@field get fun(self: Async<T>): T

-- Enums ---------------------------------------------------------------------------------------------
-- Teal declares each enum as a record whose fields are values of the record's own type.

---@class Carrier
---@field ROAD Carrier
---@field RAIL Carrier
---@field TRAM Carrier
---@field AIR Carrier
---@field WATER Carrier

---@class TransportVehicleState
---@field IN_DEPOT TransportVehicleState
---@field EN_ROUTE TransportVehicleState
---@field AT_TERMINAL TransportVehicleState
---@field GOING_TO_DEPOT TransportVehicleState

---@class BaseEdgeType
---@field NORMAL BaseEdgeType
---@field BRIDGE BaseEdgeType
---@field TUNNEL BaseEdgeType

---@class RoadType
---@field STREET RoadType
---@field TRACK RoadType

---@class TransportMode

---The values of a line problem (UtilLine.getLineProblems).
---@class LineProblem
---@field NOTHING integer
---@field ZERO_OR_ONE_STATION integer
---@field DOUBLE_STATIONS integer
---@field INCOMPATIBLE_STATIONS integer
---@field NO_PATH integer
---@field BAD_ALTERNATIVE_TERMINAL integer

---@class ScriptParamType
---@field Slider ScriptParamType

---Input, output or storage stock (members not read here).
---@class StockListType

---@class InputMode
---@field Undefined InputMode before the first input
---@field KeyboardMouse InputMode
---@field Gamepad InputMode

---@class Enum
---@field Carrier Carrier
---@field TransportVehicleState TransportVehicleState
---@field BaseEdgeType BaseEdgeType
---@field RoadType RoadType
---@field LineProblem LineProblem
---@field ScriptParamType ScriptParamType
---@field InputMode InputMode

---Journal entry categories. apidef only declares `global type JournalEntry`; the members are the
---ones the game's own code reads.
---@class JournalEntry
---@field Type JournalEntry.Type
---@field Maintenance JournalEntry.Maintenance

---@class JournalEntry.Type
---@field INCOME JournalEntry.Type
---@field SUBSIDY JournalEntry.Type
---@field MAINTENANCE JournalEntry.Type
---@field ACQUISITION JournalEntry.Type
---@field CONSTRUCTION JournalEntry.Type

---@class JournalEntry.Maintenance
---@field VEHICLE JournalEntry.Maintenance
---@field INFRASTRUCTURE JournalEntry.Maintenance
---@field VEHICLE_MAINTENANCE JournalEntry.Maintenance

---@class JournalEntry.Construction

---@class JournalEntry.Carrier

---@class JournalEntry.Other

-- Vectors -------------------------------------------------------------------------------------------

---@class Vec2i
---@field x integer
---@field y integer
local Vec2i = {}

---@param x integer
---@param y integer
---@return Vec2i
function Vec2i.new(x, y) end

---@class Vec2f
---@field x number
---@field y number
local Vec2f = {}

---@param x number
---@param y number
---@return Vec2f
function Vec2f.new(x, y) end

---@class Vec3f
---@field x number
---@field y number
---@field z number
local Vec3f = {}

---@param x number
---@param y number
---@param z number
---@return Vec3f
function Vec3f.new(x, y, z) end

---@class Vec4f
---@field x number
---@field y number
---@field z number
---@field w number
local Vec4f = {}

---@param v Vec3f
---@param w number
---@return Vec4f
---@overload fun(x: number, y: number, z: number, w: number): Vec4f
function Vec4f.new(v, w) end

---@class Box2f
---@field min Vec3f
---@field max Vec3f

-- Transport network ---------------------------------------------------------------------------------

---@class NodeId
---@field entity Engine.Entity
---@field index integer

---@class EdgeId
---@field entity Engine.Entity
---@field index integer

---A line waypoint.
---@class Waypoint
---@field tag integer

---@class LaneConfig
---@field speed number

---@class StationTerminal
---Zero-based station index in the station group.
---@field station integer
---Zero-based terminal index in the station.
---@field terminal integer
local StationTerminal = {}

---@param station integer zero-based
---@param terminal integer zero-based
---@return StationTerminal
function StationTerminal.new(station, terminal) end

---@class CargoTypeSet
---@field cargoClassesIncluded string[]

---@class Terminal.TerminalCargoTransferSpeed
---@field cargoTypeSet CargoTypeSet

---@class Terminal
---The node where the vehicle stops.
---@field vehicleNodeId NodeId
---@field cargoLoad boolean
---@field passengersLoad boolean
---@field cargoUnload boolean
---@field passengersUnload boolean
---@field cargoTransferSpeeds Terminal.TerminalCargoTransferSpeed[]

---@class Station
---@field terminals Terminal[]

-- Vehicles ------------------------------------------------------------------------------------------

---@class VehiclePart
---@field modelId integer

---@class TransportVehiclePart
---@field part VehiclePart
---Game time when this part was bought.
---@field purchaseTime integer

---@class TransportVehicleConfig
---All parts in order.
---@field vehicles TransportVehiclePart[]
local TransportVehicleConfig = {}

---@param copy TransportVehicleConfig
---@return TransportVehicleConfig
function TransportVehicleConfig.new(copy) end

-- Resources -----------------------------------------------------------------------------------------

---@class ModelMetadata.Description
---@field name string

---@class ModelMetadata.Maintenance
---@field lifespan integer

---Teal types Model.metadata as `table`: its keys hold the ModelMetadata.* records (the game casts
---them), and each may be absent.
---@class ModelMetadata
---@field description? ModelMetadata.Description
---@field maintenance? ModelMetadata.Maintenance

---@class Model
---@field metadata ModelMetadata

---@class CargoType
---@field name string

---@class CargoClass
---@field name string
---@field color Vec3f

---@class StreetTemplate
---@field laneConfigs LaneConfig[]
---@field streetStyle ResName
---@field minCurveRadiusBuild number
---@field maxSlopeBuild number

---The metadata of a construction description (passed through, no fields read here).
---@class ConstructionDescMetadata

---A generic game resource.
---@class GenericGameRes
---@field type string
---Any serializable data.
---@field data table

-- Finance -------------------------------------------------------------------------------------------

---@class ChartConfig
---The time in which the data gets collected.
---@field interval integer
---The desired number of intervals.
---@field count integer
local ChartConfig = {}

---@return ChartConfig
function ChartConfig.new() end

---@class FinanceData
---@field loan integer[]
---@field interest integer[]
---@field loanBorrowing integer[]
---@field loanRepayment integer[]
---@field total integer[]
---@field balance integer[]
---@field header string[]
---@field foreach_investment fun(self: FinanceData, fn: fun(key: integer, values: integer[]))
---@field foreach_other fun(self: FinanceData, fn: fun(key: JournalEntry.Other, values: integer[]))
local FinanceData = {}

---{type, maintenance, construction} of a row key.
---@param key integer
---@return [JournalEntry.Type, JournalEntry.Maintenance, JournalEntry.Construction]
function FinanceData:unfoldKey(key) end

---@param fn fun(carrier: JournalEntry.Carrier, rows: table<integer, integer[]>)
function FinanceData:foreach_carrier(fn) end

---@param fn fun(key: integer, values: integer[])
---@param carrier JournalEntry.Carrier
function FinanceData:foreach_transport(fn, carrier) end

---The company's value.
---@class CompanyValue
---@field totalAssets integer
---@field balance integer
---@field debt integer

-- Lines ---------------------------------------------------------------------------------------------

---@class LineIssue.Type
---@field LineCargoConfig LineIssue.Type

---@class LineIssue
---@field Type LineIssue.Type
---@field type LineIssue.Type
---@field stopIndex integer
---@field cargoType CargoTypeId

-- Proposals -----------------------------------------------------------------------------------------

---@class Context
---@field player Engine.Entity
local Context = {}

---@return Context
function Context.new() end

---An entity with a BaseNode component.
---@class Proposal.NodeAndEntity
---@field entity Engine.Entity
---@field comp Engine.Component.BaseNode
local NodeAndEntity = {}

---@return Proposal.NodeAndEntity
function NodeAndEntity.new() end

---An entity with a BaseEdge component.
---@class Proposal.SegmentAndEntity
---@field entity Engine.Entity
---@field comp Engine.Component.BaseEdge
---0 = street, 1 = track
---@field type integer
local SegmentAndEntity = {}

---@return Proposal.SegmentAndEntity
function SegmentAndEntity.new() end

---The street part of a Proposal.
---@class Proposal.StreetProposal
---@field addedSegments Proposal.SegmentAndEntity[]
---@field addedSegments_native Vector<Proposal.SegmentAndEntity>
---@field removedSegments Proposal.SegmentAndEntity[]

---A build proposal, as the construction tools hand it around (userdata).
---@class Proposal
---@field proposal Proposal.StreetProposal
---@field toRemove_native Vector<Engine.Entity>

---Data computed for a Proposal (members not read here).
---@class ProposalData

---New entities get negative ids, from -1 down.
---@class SimpleStreetProposal
---@field nodesToAdd Proposal.NodeAndEntity[]
---@field edgesToAdd Proposal.SegmentAndEntity[]
---@field nodesToRemove Engine.Entity[]
---@field edgesToRemove Engine.Entity[]

---@class SimpleProposal
---@field streetProposal SimpleStreetProposal
local SimpleProposal = {}

---@return SimpleProposal
function SimpleProposal.new() end

-- Map layers ----------------------------------------------------------------------------------------

---@class LayerConfig.CatchmentAreaDisplaySettings
---@field borderAlpha number
---@field godrayAlpha number
---@field innerAlpha number
local CatchmentAreaDisplaySettings = {}

---@return LayerConfig.CatchmentAreaDisplaySettings
function CatchmentAreaDisplaySettings.new() end

---@class LayerConfig.CatchmentAreaRenderableConfig
---@field isVisible boolean
---@field displaySettings LayerConfig.CatchmentAreaDisplaySettings
---@field cargo boolean
---@field person boolean
---Only the areas of this entity (-1 = all).
---@field entity Engine.Entity
local CatchmentAreaRenderableConfig = {}

---@return LayerConfig.CatchmentAreaRenderableConfig
function CatchmentAreaRenderableConfig.new() end

---Industry plots.
---@class LayerConfig.PlotsRenderableConfig
---@field triangles Vec2f[]
local PlotsRenderableConfig = {}

---@return LayerConfig.PlotsRenderableConfig
function PlotsRenderableConfig.new() end

---@class LayerConfig
---@field CatchmentAreaDisplaySettings LayerConfig.CatchmentAreaDisplaySettings
---@field CatchmentAreaRenderableConfig LayerConfig.CatchmentAreaRenderableConfig
---@field PlotsRenderableConfig LayerConfig.PlotsRenderableConfig
---@field catchmentAreaRenderableConfig LayerConfig.CatchmentAreaRenderableConfig
---@field plotsRenderableConfig LayerConfig.PlotsRenderableConfig
local LayerConfig = {}

---@return LayerConfig
function LayerConfig.new() end

-- Savegames and mods --------------------------------------------------------------------------------

---@class Mod.ModId
---A string that identifies the mod.
---@field name string
local ModId = {}

---@return Mod.ModId
function ModId.new() end

---@class SaveGameId
---@field path string
---@field saveGameName string
---@field saveGameNamespace string
local SaveGameId = {}

---@return SaveGameId
function SaveGameId.new() end

---@class SaveGameInfo
---@field path string
---@field saveName string

---@class SaveGameData.SaveGameDetails
---@field mods Mod.ModId[]
---Mod params by mod id, then param key: the chosen value's index (api/tealdef/api/type.d.tl).
---@field modParams table<string, table<string, integer>>
local SaveGameDetails = {}

---@param copy SaveGameData.SaveGameDetails
---@return SaveGameData.SaveGameDetails
function SaveGameDetails.new(copy) end

---@class SaveGameData
---Error message if loading failed (empty string otherwise).
---@field errorMsg string
---@field info SaveGameData.SaveGameDetails

---@class StartGameParams
---Map size in tiles.
---@field numTiles Vec2i
---@field climateGenerator string
---@field terrainGenerator string
---@field economy string
---Ids of the mods to load.
---@field mods string[]
---@field seed string
---@field generateTowns boolean
---@field generateIndustries boolean
---@field generateAssets boolean
---Mod params by mod id, then param key: the chosen value's index.
---@field modParams table<string, table<string, integer>>
local StartGameParams = {}

---@return StartGameParams
function StartGameParams.new() end

---@class AppConfig
---Prefix for money display.
---@field moneyPrefix string

-- api.type ------------------------------------------------------------------------------------------

---The types namespace (`api.type`).
---@class Type
---@field ModId Mod.ModId
---@field enum Enum
---@field Vec4f Vec4f
---@field Vec3f Vec3f
---@field Vec2f Vec2f
---@field Vec2i Vec2i
---@field ComponentType Engine.ComponentType
---@field JournalEntry JournalEntry
---@field StationTerminal StationTerminal
---@field Line Engine.Component.Line
---@field TransportVehicleConfig TransportVehicleConfig
---@field Context Context
---@field SimpleProposal SimpleProposal
---@field LayerConfig LayerConfig
---@field StartGameParams StartGameParams
---@field SavegameId SaveGameId
---@field SaveGameDetails SaveGameData.SaveGameDetails
---@field ChartConfig ChartConfig
---@field NodeAndEntity Proposal.NodeAndEntity
---@field SegmentAndEntity Proposal.SegmentAndEntity
---@field LineIssue LineIssue
