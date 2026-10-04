---@meta

---@alias game.gui.line_vehicle_mgmt.line_util.RelaxationType "Catenary"|"Road"|"Train"|"TramLanes"|"TramTrack"

---@alias game.gui.line_vehicle_mgmt.line_util.LVMMode "MAIN"|"SEND_TO_LINE"|"SEGMENT"|"MOVE_STOP"|"MOVE_WAYPOINT"

---A station (and terminal) picked in the Line Manager (LineUtil.StationSelectionDetails).
---@class game.gui.line_vehicle_mgmt.line_util.StationSelectionDetails
---@field stationGroup Engine.Entity
---@field stationIndex1? integer 1-based index in stationGroup; nil if no station is picked
---@field station? Engine.Entity
---@field terminalIndex1? integer 1-based index in the station; nil if no terminal is picked
---@field flatStationTerminalIndex1? integer 1-based index in all station/terminal pairs of the group

---What the Line Manager passes to its parts (CommonActionParams), the fields this repo uses.
---@class game.gui.line_vehicle_mgmt.line_util.CommonActionParams
---@field gameCtx game.gui.main.game_context.GameContext
---@field lineState react.State<game.gui.line_vehicle_mgmt.line.ReactLine>
---@field vehicleManagerStateRef react.Ref<game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState>
---@field lineManagerStateRef react.Ref<game.gui.line_vehicle_mgmt.manager_window.LineManagerState>
---@field vehicleManagerRef react.RefWrapApi<game.gui.line_vehicle_mgmt.manager_window.VehicleManagerApi>
---@field getModeState fun(): [game.gui.line_vehicle_mgmt.line_util.LVMMode, any] any: the mode's data, e.g. the stop number of a SEGMENT
---@field addFeedback fun(message: string, mode: string, dialogData?: game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackDialogParam, id?: number)
---@field newLine fun(newLineStartingWithStation: game.gui.line_vehicle_mgmt.line_util.StationSelectionDetails, vehicleEntities: Engine.Entity[])

---@class game.gui.line_vehicle_mgmt.line_util
local M = {}

---The line's stops for its update command, with terminals assigned.
---@param entity Engine.Entity line
---@param path game.gui.line_vehicle_mgmt.line.ReactVia[]
---@return Engine.Component.Line.Stop[]
function M.autoAssignTerminals(entity, path) end

---@param lineEntity Engine.Entity
---@return game.gui.line_vehicle_mgmt.line.ReactLine
function M.getReactLineFromGameState(lineEntity) end

---@param entityId Engine.Entity line
---@return integer
function M.calculateFrequencySeconds(entityId) end

---@param vehicleEntity Engine.Entity
---@return string
function M.getVehicleInstructionName(vehicleEntity) end

---@param stationEntity Engine.Entity
---@param terminalIndex1 integer
---@return number
function M.getTerminalLength(stationEntity, terminalIndex1) end

---What the stop would need relaxed to be reachable, nil if nothing.
---@param okModes table<TransportMode, boolean>
---@param relaxedModes table<TransportMode, boolean>
---@param allowedModes table<TransportMode, boolean>
---@return game.gui.line_vehicle_mgmt.line_util.RelaxationType?
function M.getRelaxationType(okModes, relaxedModes, allowedModes) end

---@param relaxationType game.gui.line_vehicle_mgmt.line_util.RelaxationType
---@return string
function M.getRelaxationText(relaxationType) end

---Whether the line has vehicles of one of `allowedCarriers`.
---@param allowedCarriers Carrier[]
---@param lineEntity Engine.Entity
---@return boolean
function M.filterLine(allowedCarriers, lineEntity) end

return M
