--- Plugin body for ::ModEntryPointExtension: an invisible root that runs the one-time cleanup, keeps
-- the mission's protected entities for actions.lua, sells retired vehicles once they are in a depot
-- (actions.step, after actions.rescue on mount) and owns the mod's "uio.action" event
-- ({ name, entity }: add_vehicle, remove_vehicle, clone_vehicle, retire_vehicle, open_entity,
-- open_line_manager), which other mods and the testbench use. Rendered by the guarded stub
-- entry.script.lua.
-- @module ui_overhaul.gui.entry
local react = require("::/gui/main/react.lua")
local actions = require("/ui_overhaul/gui/actions.lua")
local cleanup = require("/ui_overhaul/gui/cleanup.lua")
local lvm_tweaks = require("/ui_overhaul/gui/lvm_tweaks.lua")
local ui = require("/ui_overhaul/gui/ui.lua")
local guard = require("/ui_overhaul/gui/guard.lua")

---@class uo.gui.entry
local entry = {}

local report = guard.reporter("entry: ")

-- Runs fn(...); an error is logged once under `key` instead of escaping the event or step callback.
---@param key string
---@param fn fun(...: any)
---@param ... any passed on unchanged
local function safely(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then report(key, err) end
end

---@return react.TreeNodeId
function entry.render()
	-- other mods send this event with whatever they like: an error must not escape the callback
	react.onEvent(actions.ACTION_EVENT, function(_e, param)
		safely("action " .. tostring(type(param) == "table" and param.name or param), actions.run, param)
	end)
	-- The entry point mounts with the game's UI root, which keeps gameCtx.filters the same way
	-- (game.tl), so the copy sees every change a mission makes.
	react.onEvent("setProtectedEntities", function(_e, param)
		safely("protected entities", actions.set_protected_entities, param)
	end)
	react.onEvent("openVehicleManager", function(_e, param) safely("Line Manager open", lvm_tweaks.on_open, param) end)
	-- testbench: replace `vehicles` with identical configs the way the vehicle store does; expects the
	-- Line Manager's question instead of an immediate replace
	---@param _e string
	---@param vehicles Engine.Entity[]
	react.onEvent("uio.debug.replace", function(_e, vehicles)
		local vehicle_react_util = require("::/gui/line_vehicle_mgmt/vehicle_react_util.tl")
		local changes = {} ---@type game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleChange[]
		for _i, v in ipairs(vehicles) do
			local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
			if tv then
				local config = api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)
				changes[#changes + 1] = { vehicleEntity = v, config = config }
			end
		end
		vehicle_react_util.HandleVehicleChanges(changes, actions.protected_entities(), nil, nil, nil, nil)
	end)
	-- testbench: which features are shown, and which mod won where both change the same part
	react.onEvent("uio.debug.priority", function()
		safely("priority", function()
			local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")
			for _i, line in ipairs(priority.describe()) do debugPrint("[ui_overhaul] feature ", line) end
		end)
	end)
	-- testbench: the bulldozer warning for a proposal that removes `entity`
	---@param _e string
	---@param entity Engine.Entity
	react.onEvent("uio.debug.bulldoze", function(_e, entity)
		local construction = require("ui_overhaul_1::/ui_overhaul/gui/construction.lua")
		local fake = { toRemove_native = { size = function() return 1 end, at = function() return entity end } }
		-- a stand-in with only toRemove_native, the one member station_warnings reads
		---@diagnostic disable-next-line: param-type-mismatch
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
	-- testbench: the tool stack the game reaches through game_react_globals (fallback.lua), checked in
	-- the UI's own Lua state (the testbench script has another one, where react.lua would load again)
	react.onEvent("uio.debug.tool_stack", function()
		safely("tool stack check", function()
			local globals = require("::/gui/main/game_react_globals.tl") --[[@as game.gui.main.game_react_globals]]
			local ok, tool = pcall(function() return globals.getDefaultToolStackApi().getActiveTool() end)
			local name = ok and tool and tool.name or tostring(tool)
			debugPrint("[ui_overhaul] tool stack api: active tool=", tostring(name),
				(ok and tool ~= nil) and " ok" or " check failed")
		end)
	end)
	-- testbench: the installed section functions, driven like vehicle.tl does (a key no real card
	-- uses): open in one window, remembered by the next, closed there by Modify's "collapse all"
	react.onEvent("uio.debug.sections", function()
		safely("sections check", function()
			local content_card = require("::/gui/main/content_card.tl")
			local function window()
				local value = {} ---@type table<string, boolean>
				---@type react.State<table<string, boolean>>
				local state = {
					old = function() return value end,
					set = function(_self, v) value = v end,
					---@param _self any the state, unused
					---@param fn fun(old: table<string, boolean>): table<string, boolean>
					transform = function(_self, fn) value = fn(value) end,
					hasExpired = function() return false end,
				}
				local update, is_expanded = content_card.makeContentCardsCollapsibleFunctions(state, true)
				return { update = update, is_expanded = is_expanded }
			end
			local key = "uio.testbench.section"
			window().update(key, true)
			local second = window()
			local remembered = second.is_expanded(key)
			second.update("", false)
			local collapsed = not second.is_expanded(key)
			local next_window = window().is_expanded(key)
			window().update(key, false)
			debugPrint("[ui_overhaul] sections: remembered=", tostring(remembered), " collapsed=", tostring(collapsed),
				" next window=", tostring(next_window),
				(remembered and collapsed and next_window) and " ok" or " check failed")
		end)
	end)
	react.onMount(function() safely("vehicles to be sold on arrival", actions.rescue) end)
	-- testbench: the same once more, for a vehicle it has just sent with the flag
	react.onEvent("uio.debug.rescue", function() safely("vehicles to be sold on arrival", actions.rescue) end)
	react.onStep(function()
		safely("retired vehicles", actions.step)
		safely("cleanup", cleanup.step)
		safely("Line Manager step", lvm_tweaks.step)
	end)
	return ui.row({})
end

return entry
