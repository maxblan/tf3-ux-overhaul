---@meta
-- Types of gui/entity_window/vehicle/vehicle_eow.d.tl (no module of its own here).

---@class game.gui.entity_window.vehicle.vehicle_eow.StaticVehicleInfoState
---@field modelIds integer[]
---@field carrier Carrier
---@field modifiers Engine.Component.TransportVehicle.Modifiers
---@field canTransportPassengers boolean
---@field vehicleSpecialization string[]

---@class game.gui.entity_window.vehicle.vehicle_eow.VehicleEowState
---@field staticVehicleInfo game.gui.entity_window.vehicle.vehicle_eow.StaticVehicleInfoState

---Params of the vehicle window's widget plugins (VehicleEow.VehicleWidgetPluginParams).
---@class game.gui.entity_window.vehicle.vehicle_eow.VehicleWidgetPluginParams: game.gui.entity_window.eow_extension_util.IEowWidgetsExtensionParams
---@field state game.gui.entity_window.vehicle.vehicle_eow.VehicleEowState
