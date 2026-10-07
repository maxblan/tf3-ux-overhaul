---@meta
-- Types of gui/line_vehicle_mgmt/manager_window.d.tl (no module of its own here).

---Api of the vehicle manager (the Line Manager's vehicle half).
---@class game.gui.line_vehicle_mgmt.manager_window.VehicleManagerApi
---@field addVehiclesToVehicleListAndSelect fun(vehicleEntities: Engine.Entity[])
---@field removeVehiclesFromVehicleList fun(vehicleEntities: Engine.Entity[])
---@field clearVehicleList fun()
---@field selectVehicles fun(vehicleEntities: Engine.Entity[], selectEntities: boolean)
---@field isVehicleSelected fun(vehicleEntity: Engine.Entity): boolean
---@field numberSelectedVehicles fun(): integer
---@field closeVehicleStore fun()

---@class game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState
---@field vehicleListEntitiesSelected game.scripts.entity_util.EntityAndRevision[]
---@field vehicleListEntitiesUnselected game.scripts.entity_util.EntityAndRevision[]
---@field carriers Carrier[]

---@class game.gui.line_vehicle_mgmt.manager_window.LineManagerState
---@field lineListEntitiesSelected game.scripts.entity_util.EntityAndRevision[]
---@field lineListEntitiesUnselected game.scripts.entity_util.EntityAndRevision[]
---@field depotListEntitiesSelected game.scripts.entity_util.EntityAndRevision[]
---@field depotListEntitiesUnselected game.scripts.entity_util.EntityAndRevision[]

---The "duplicateVehicles" event's param (DuplicateVehiclesParam).
---@class game.gui.line_vehicle_mgmt.manager_window.DuplicateVehiclesParam
---@field vehicleEntities Engine.Entity[]
---@field addFeedback fun(message: string, mode: string, dialogData?: game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackDialogParam, id?: number)
---@field onBuy fun(resultEntities: [Engine.Entity, Engine.Revision][])

---The "openVehicleManager" event's param (ManagerWindow.ManagerWindowEventParam).
---@class game.gui.line_vehicle_mgmt.manager_window.ManagerWindowEventParam
---@field openWithLineEntity? Engine.Entity
---@field openWithDepotEntity? Engine.Entity
---@field openWithVehicleEntities? Engine.Entity[]
---@field sendToLineMode? boolean

---The Line Manager tool's params (ManagerWindow.ManagerToolParam), the fields this repo uses.
---@class game.gui.line_vehicle_mgmt.manager_window.ManagerToolParam
---@field lineManagerStateRef react.Ref<game.gui.line_vehicle_mgmt.manager_window.LineManagerState>
