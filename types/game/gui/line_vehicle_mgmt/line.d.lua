---@meta
-- Types of gui/line_vehicle_mgmt/line.d.tl (no module of its own here).

---Stop data a line keeps for the update command; the line editor does not use it.
---@class game.gui.line_vehicle_mgmt.line.PassThroughStopData
---@field minWaitingTime number
---@field maxWaitingTime number
---@field maxAdditionalWaitingTime number
---@field stopConfig Engine.Component.Line.StopConfig
---@field loadMode Engine.Component.Line.LoadMode

---A stop of a line as the Line Manager edits it (Line.ReactTerminal).
---@class game.gui.line_vehicle_mgmt.line.ReactTerminal
---@field stationGroup Engine.Entity
---@field station1 integer 1-based index in stationGroup
---@field terminal1 integer 1-based index in the station
---@field alternativeTerminals StationTerminal[]
---@field loadMode Engine.Component.Line.LoadMode
---@field passThroughStopData game.gui.line_vehicle_mgmt.line.PassThroughStopData

---A stop or a waypoint of a line (Line.ReactVia).
---@class game.gui.line_vehicle_mgmt.line.ReactVia
---@field waypoint? Waypoint nil if not a waypoint
---@field stop? game.gui.line_vehicle_mgmt.line.ReactTerminal

---A line as the Line Manager edits it (Line.ReactLine).
---@class game.gui.line_vehicle_mgmt.line.ReactLine
---@field entityAndRevision game.scripts.entity_util.EntityAndRevision
---@field path game.gui.line_vehicle_mgmt.line.ReactVia[]
---@field customFilters boolean
---@field reservationPriority number
---@field maxWaypointTag integer
---@field color Vec3f
---@field carrierFilter table<Carrier, boolean>
