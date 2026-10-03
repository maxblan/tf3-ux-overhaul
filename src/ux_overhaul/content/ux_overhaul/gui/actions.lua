--- Player actions behind the mod's buttons. Wherever possible they go through the base game's own
-- events, so the base checks (mission locks, money, depots) apply. GUI thread only.
-- API references: docs/api_cookbook.md §6.
-- @module ux_overhaul.gui.actions
local react = require("::/gui/main/react.lua")
local store = require("/ux_overhaul/engine/store.lua")

local actions = {}

local TAG = "[ux_overhaul]"

--- Event that opens the Control Center; param { tab = "problems"|"lines", filter = <lines filter> }.
actions.OPEN_EVENT = "uxo.open"

function actions.open_control_center(tab, filter)
	react.fireEvent(nil, actions.OPEN_EVENT, { tab = tab, filter = filter })
end

--- Opens the entity's window on top of the others and moves the camera to it.
function actions.open_entity(entity)
	if not entity or not api.engine.entityExists(entity) then return end
	api.gui.camera.focusEntity(entity)
	react.fireEvent(nil, "selectEntity", { entity = entity, stack = true })
end

function actions.open_line_manager(line)
	react.fireEvent(nil, "openVehicleManager", { openWithLineEntity = line })
end

function actions.open_finances(tab)
	react.fireEvent(nil, "openFinanceWindow", tab)
end

function actions.open_statistics(tab)
	react.fireEvent(nil, "openStatisticsWindow", tab or "Line")
end

local function purchase_time(vehicle)
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	local oldest
	for _i, part in ipairs(tv and tv.transportVehicleConfig.vehicles or {}) do
		if oldest == nil or part.purchaseTime < oldest then oldest = part.purchaseTime end
	end
	return oldest or 0
end

--- The line's newest (`newest` = true) or oldest vehicle, or nil.
local function line_vehicle(line, newest)
	local best, best_time
	for _i, vehicle in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
		local t = purchase_time(vehicle)
		if best == nil or (newest and t > best_time) or (not newest and t < best_time) then
			best, best_time = vehicle, t
		end
	end
	return best
end

local function feedback(message)
	debugPrint(TAG, " ", tostring(message))
end

--- Buys a copy of the line's newest vehicle and sends it onto the line. Uses the base
-- "duplicateVehicles" handler (vehicle window "Clone"), which also checks money and mission locks.
-- Returns false if the line has no vehicle to copy.
function actions.add_vehicle(line)
	local template = line_vehicle(line, true)
	if not template then return false end
	react.fireEvent(nil, "duplicateVehicles", {
		vehicleEntities = { template },
		addFeedback = feedback,
		-- Without onBuy the base handler buys the clone but leaves it in the depot.
		onBuy = function() store.invalidate() end,
	})
	return true
end

--- Sends the line's oldest vehicle to a depot, where it is sold on arrival.
-- Returns false if the line has no vehicle.
function actions.remove_vehicle(line)
	local oldest = line_vehicle(line, false)
	if not oldest then return false end
	api.cmd.sendCommand(api.cmd.makeVehicleSendToDepotCmd(oldest, true), function(_e, success)
		if not success then feedback("vehicle could not be sent to a depot") end
		store.invalidate()
	end)
	return true
end

--- Event that runs an action by name; param { name, entity }.
actions.ACTION_EVENT = "uxo.action"

local BY_NAME = { "add_vehicle", "remove_vehicle", "open_entity", "open_line_manager" }

--- Runs the action `param.name` on `param.entity`; logs and ignores unknown names.
function actions.run(param)
	param = param or {}
	for _i, name in ipairs(BY_NAME) do
		if name == param.name then
			local ok = actions[name](param.entity)
			debugPrint(TAG, " action ", name, " ", tostring(param.entity), " -> ", tostring(ok ~= false))
			return
		end
	end
	feedback("unknown action " .. tostring(param.name))
end

--- Saves under the current savegame name, like the quicksave key. A game that was never saved has
-- no name yet: then the pause menu opens, where the player picks one.
function actions.save_game()
	local name = api.gui.game.getDefaultSavegameId()
	if name == nil or name == "" then
		react.fireEvent(nil, "openPauseMenu")
		return
	end
	app.saveGame(name, function() feedback("saved " .. tostring(name)) end, api.gui.game.isMapEditor(), true)
end

return actions
