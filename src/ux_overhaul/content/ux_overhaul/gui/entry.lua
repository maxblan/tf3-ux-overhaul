--- Plugin body for ::ModEntryPointExtension: an invisible root that keeps the shared snapshot fresh,
-- runs the one-time cleanup and owns the mod's "uxo.action" event ({ name, entity }: add_vehicle,
-- remove_vehicle, clone_vehicle, retire_vehicle, open_entity, open_line_manager), which other mods and
-- the testbench use. Rendered by the guarded stub entry.script.lua.
-- @module ux_overhaul.gui.entry
local react = require("::/gui/main/react.lua")
local store = require("/ux_overhaul/engine/store.lua")
local actions = require("/ux_overhaul/gui/actions.lua")
local cleanup = require("/ux_overhaul/gui/cleanup.lua")
local lvm_tweaks = require("/ux_overhaul/gui/lvm_tweaks.lua")
local defer = require("/ux_overhaul/gui/defer.lua")
local ui = require("/ux_overhaul/gui/ui.lua")

local entry = {}

function entry.render()
	react.onEvent(actions.ACTION_EVENT, function(_e, param) actions.run(param) end)
	react.onStepTimer(store.refresh, store.REFRESH_SECONDS)
	react.onEvent("openVehicleManager", function(_e, param) lvm_tweaks.on_open(param) end)
	-- testbench: send a clone of `vehicles` the way the Line Manager does; expects the confirmation
	react.onEvent("uxo.debug.clone", function(_e, vehicles)
		react.fireEvent(nil, "duplicateVehicles", {
			vehicleEntities = vehicles,
			addFeedback = function(text, mode) debugPrint("[ux_overhaul] feedback ", tostring(mode), " ", tostring(text)) end,
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
