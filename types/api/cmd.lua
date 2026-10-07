---@meta
-- api.cmd, typed after apidef/api/cmd.d.tl. Only what this repository uses.

---Command data payload.
---@class ICommandData

---A command for sendCommand.
---@class Command<T>

---@class EntitySetNameCommandData: ICommandData
---@class GameSetSpeedCommandData: ICommandData
---@class LineUpdateCommandData: ICommandData
---@class ScriptingSendEventCommandData: ICommandData
---@class VehicleSendToDepotCommandData: ICommandData
---@class VehicleReplaceCommandData: ICommandData
---@class WorldBuildProposalCommandData: ICommandData

---The commands (`api.cmd`).
---@class Cmd
---When executed, the entity is renamed; unless forceSameEntity, a station sets the stem name instead.
---@field makeEntitySetNameCmd fun(entity: Engine.Entity, name: string, forceSameEntity?: boolean): Command<EntitySetNameCommandData>
---@field makeGameSetSpeedCmd fun(speedup: integer): Command<GameSetSpeedCommandData>
---@field makeLineUpdateCmd fun(lineEntity: Engine.Entity, data: Engine.Component.Line): Command<LineUpdateCommandData>
local Cmd = {}

---Runs the command later or now, depending on the context, then calls `callback`. Game scripts may
---not pass a callback.
---@generic T: ICommandData
---@param cmd Command<T>
---@param callback? fun(data: T, success: boolean)
function Cmd.sendCommand(cmd, callback) end

---@param src string
---@param id string
---@param name string
---@param param any any data the receiving script accepts
---@return Command<ScriptingSendEventCommandData>
function Cmd.makeScriptingSendEventCmd(src, id, name, param) end

---@param vehicleEntity Engine.Entity
---@param sellOnArrival boolean
---@param jumpToDepoEntity? Engine.Entity
---@return Command<VehicleSendToDepotCommandData>
function Cmd.makeVehicleSendToDepotCmd(vehicleEntity, sellOnArrival, jumpToDepoEntity) end

---@param vehicleEntity Engine.Entity
---@param tvc TransportVehicleConfig
---@return Command<VehicleReplaceCommandData>
function Cmd.makeVehicleReplaceCmd(vehicleEntity, tvc) end

---@param proposal SimpleProposal
---@param context Context
---@param ignoreErrors boolean
---@param playerInitiated boolean
---@param doDust? boolean
---@return Command<WorldBuildProposalCommandData>
function Cmd.makeWorldBuildProposalCmd(proposal, context, ignoreErrors, playerInitiated, doDust) end
