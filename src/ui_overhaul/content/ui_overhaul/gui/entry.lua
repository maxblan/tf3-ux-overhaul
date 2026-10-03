--- Plugin body for ::ModEntryPointExtension: an invisible root that keeps the shared snapshot fresh,
-- runs the one-time cleanup and owns the mod's "uio.action" event ({ name, entity }: add_vehicle,
-- remove_vehicle, clone_vehicle, retire_vehicle, open_entity, open_line_manager), which other mods and
-- the testbench use. Rendered by the guarded stub entry.script.lua.
-- @module ui_overhaul.gui.entry
local react = require("::/gui/main/react.lua")
local store = require("/ui_overhaul/engine/store.lua")
local actions = require("/ui_overhaul/gui/actions.lua")
local cleanup = require("/ui_overhaul/gui/cleanup.lua")
local lvm_tweaks = require("/ui_overhaul/gui/lvm_tweaks.lua")
local defer = require("/ui_overhaul/gui/defer.lua")
local ui = require("/ui_overhaul/gui/ui.lua")

local entry = {}

function entry.render()
	react.onEvent(actions.ACTION_EVENT, function(_e, param) actions.run(param) end)
	react.onStepTimer(store.refresh, store.REFRESH_SECONDS)
	react.onEvent("openVehicleManager", function(_e, param) lvm_tweaks.on_open(param) end)
	-- testbench: replace `vehicles` with identical configs the way the vehicle store does; expects the
	-- Line Manager's question instead of an immediate replace
	react.onEvent("uio.debug.replace", function(_e, vehicles)
		local vehicle_react_util = require("::/gui/line_vehicle_mgmt/vehicle_react_util.tl")
		local changes = {}
		for _i, v in ipairs(vehicles) do
			local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
			local config = api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)
			changes[#changes + 1] = { vehicleEntity = v, config = config }
		end
		vehicle_react_util.HandleVehicleChanges(changes, {}, nil, nil, nil, nil)
	end)
	-- testbench: the bulldozer warning for a proposal that removes `entity`
	react.onEvent("uio.debug.bulldoze", function(_e, entity)
		local construction = require("ui_overhaul_1::/ui_overhaul/gui/construction.lua")
		local fake = { toRemove_native = { size = function() return 1 end, at = function() return entity end } }
		for _i, text in ipairs(construction.station_warnings(fake)) do
			debugPrint("[ui_overhaul] bulldozer warning: ", text)
		end
	end)
	-- testbench: send a clone of `vehicles` the way the Line Manager does; expects the confirmation
	react.onEvent("uio.debug.clone", function(_e, vehicles)
		react.fireEvent(nil, "duplicateVehicles", {
			vehicleEntities = vehicles,
			addFeedback = function(text, mode) debugPrint("[ui_overhaul] feedback ", tostring(mode), " ", tostring(text)) end,
			onBuy = function() end,
		})
	end)
	react.onStep(function()
		cleanup.step()
		lvm_tweaks.step()
		defer.step()
	end)
	return ui.row({})
end

return entry
