--- Plugin body for ::ModEntryPointExtension: an invisible root that keeps the shared snapshot fresh,
-- runs the one-time cleanup and owns the mod's "uxo.action" event ({ name, entity }: add_vehicle,
-- remove_vehicle, clone_vehicle, retire_vehicle, open_entity, open_line_manager), which other mods and
-- the testbench use. Rendered by the guarded stub entry.script.lua.
-- @module ux_overhaul.gui.entry
local react = require("::/gui/main/react.lua")
local store = require("/ux_overhaul/engine/store.lua")
local actions = require("/ux_overhaul/gui/actions.lua")
local cleanup = require("/ux_overhaul/gui/cleanup.lua")
local ui = require("/ux_overhaul/gui/ui.lua")

local entry = {}

function entry.render()
	react.onEvent(actions.ACTION_EVENT, function(_e, param) actions.run(param) end)
	react.onStepTimer(store.refresh, store.REFRESH_SECONDS)
	react.onStep(cleanup.step)
	return ui.row({})
end

return entry
