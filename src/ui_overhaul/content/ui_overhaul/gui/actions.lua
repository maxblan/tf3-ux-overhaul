--- Player actions behind the mod's buttons. Wherever possible they go through the base game's own
-- events, so the base checks (mission locks, money, depots) apply. GUI thread only.
-- API references: docs/api_cookbook.md §6.
--
-- A vehicle is retired the way the game's own buttons allow: sent to a depot ("Send to Depot"), then
-- sold with the game's Sell once it is there (step). The engine's own sale on arrival
-- (makeVehicleSendToDepotCmd's sellOnArrival, which no base button uses) can crash the simulation
-- when the vehicle arrives, also without mods (docs/api_cookbook.md §6.2). A vehicle a savegame still
-- has on its way with that flag is sold right away (rescue): sending it again does not clear the flag
-- (observed in game).
-- @module ui_overhaul.gui.actions
local react = require("::/gui/main/react.lua")

local actions = {}

local TAG = "[ui_overhaul]"

---@alias uo.actions.FeedbackDialog game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackDialogParam
---The base handlers' addFeedback (DuplicateVehiclesParam in manager_window.d.tl).
---@alias uo.actions.Feedback fun(message: string, mode?: string, dialogData?: uo.actions.FeedbackDialog, id?: number)
---@alias uo.actions.Protected table<Engine.Entity, table|boolean>

-- Copy of gameCtx.filters:get().protectedEntities for callers without a gameCtx (the uio.action
-- event). The entry point keeps it current from the same "setProtectedEntities" event the base
-- game's filters listen to (game.tl).
---@type uo.actions.Protected
local protected_entities = {}

-- Vehicles this session sent to a depot to be sold there: vehicle -> true. Not saved: after loading a
-- savegame, a vehicle on its way stays in the depot unsold, as after the game's "Send to Depot".
---@type table<Engine.Entity, true>
local retiring = {}

--- Takes the entities a campaign mission protects, as the "setProtectedEntities" event sends them.
---@param entities? uo.actions.Protected
function actions.set_protected_entities(entities)
	protected_entities = type(entities) == "table" and entities or {}
end

--- Truthy protectedEntities entries protect, as in the base checks (vehicle.tl).
---@param vehicle Engine.Entity
---@param protected? uo.actions.Protected
---@return boolean
local function is_protected(vehicle, protected)
	return not not (protected or protected_entities)[vehicle]
end

--- Feedback without a window to show it in, e.g. for the uio.action event: the game log only.
---@type uo.actions.Feedback
local function log_feedback(message)
	debugPrint(TAG, " ", tostring(message))
end

--- Opens the entity's window on top of the others and moves the camera to it.
---@param entity Engine.Entity
function actions.open_entity(entity)
	if not entity or not api.engine.entityExists(entity) then return end
	api.gui.camera.focusEntity(entity)
	react.fireEvent(nil, "selectEntity", { entity = entity, stack = true })
end

---@param line Engine.Entity
function actions.open_line_manager(line)
	react.fireEvent(nil, "openVehicleManager", { openWithLineEntity = line })
end

---@param tv Engine.Component.TransportVehicle
---@return number
local function purchase_time(tv)
	local oldest ---@type number?
	for _i, part in ipairs(tv.transportVehicleConfig.vehicles) do
		if oldest == nil or part.purchaseTime < oldest then oldest = part.purchaseTime end
	end
	return oldest or 0
end

-- Whether the vehicle is on its way to a depot or in one: still listed under its line, but no longer
-- serving it (the vehicle window treats it as without line, vehicle.tl).
---@param tv Engine.Component.TransportVehicle
---@return boolean
local function leaving_line(tv)
	local states = api.type.enum and api.type.enum.TransportVehicleState
	return states ~= nil and (tv.state == states.GOING_TO_DEPOT or tv.state == states.IN_DEPOT)
end

--- The line's newest (`newest` = true) or oldest vehicle that still serves it, or nil. Vehicles sent
-- to a depot are skipped, so Remove Vehicle clicked again retires the next one.
---@param line Engine.Entity
---@param newest boolean
---@return Engine.Entity?
local function line_vehicle(line, newest)
	local best ---@type Engine.Entity?
	local best_time ---@type number?
	for _i, vehicle in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
		if tv and not leaving_line(tv) then
			local t = purchase_time(tv)
			if best == nil or (newest and t > best_time) or (not newest and t < best_time) then
				best, best_time = vehicle, t
			end
		end
	end
	return best
end

--- Buys an identical vehicle and sends it onto the same line, like the vehicle window's "Clone".
-- Uses the base "duplicateVehicles" handler, which checks money, mission locks and the depot, and
-- reports why it did not buy through `add_feedback` (the window's feedback list; default: the log).
---@param vehicle? Engine.Entity
---@param add_feedback? uo.actions.Feedback
---@return boolean
function actions.clone_vehicle(vehicle, add_feedback)
	if not vehicle or not api.engine.entityExists(vehicle) then return false end
	react.fireEvent(nil, "duplicateVehicles", {
		vehicleEntities = { vehicle },
		addFeedback = add_feedback or log_feedback,
		-- Without onBuy the base handler buys the clone but leaves it in the depot.
		onBuy = function() end,
	})
	return true
end

--- Sends the vehicle to a depot, where step sells it once it is there. A vehicle a mission protects
-- is not sold, as the vehicle window's "Sell" refuses it (vehicle.tl): `protected` is
-- gameCtx.filters:get().protectedEntities where the caller has it, else the copy kept from the event.
---@param vehicle? Engine.Entity
---@param add_feedback? uo.actions.Feedback
---@param protected? uo.actions.Protected
---@return boolean
function actions.retire_vehicle(vehicle, add_feedback, protected)
	if not vehicle or not api.engine.entityExists(vehicle) then return false end
	add_feedback = add_feedback or log_feedback
	if is_protected(vehicle, protected) then
		add_feedback(_("Vehicle cannot be sold at this time."), nil, nil, nil)
		return false
	end
	api.cmd.sendCommand(api.cmd.makeVehicleSendToDepotCmd(vehicle, false), function(_c, success)
		if success then
			retiring[vehicle] = true
		else
			add_feedback(_("Vehicle could not be sent to depot."), nil, nil, nil)
		end
	end)
	return true
end

--- Per-frame step of the entry point: sells the vehicles sent to be sold once they are in a depot.
-- One the player sent back onto a line (no longer on its way) is left alone; one a mission protects
-- meanwhile stays in the depot.
function actions.step()
	if next(retiring) == nil then return end
	local states = api.type.enum.TransportVehicleState
	local sell = {} ---@type Engine.Entity[]
	for vehicle in pairs(retiring) do
		local tv = api.engine.entityExists(vehicle)
			and api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) or nil
		if not tv or (tv.state ~= states.GOING_TO_DEPOT and tv.state ~= states.IN_DEPOT) then
			retiring[vehicle] = nil
		elseif tv.state == states.IN_DEPOT then
			retiring[vehicle] = nil
			-- no _() here: a step is no render (CONTRIBUTING, GUI-thread calls)
			if is_protected(vehicle) then
				log_feedback("vehicle " .. tostring(vehicle) .. " is protected now: left in the depot")
			else
				sell[#sell + 1] = vehicle
			end
		end
	end
	if #sell > 0 then
		api.cmd.sendCommand(api.cmd.makeVehicleSellCmd(sell), function(_c, success)
			if not success then log_feedback("selling vehicles in the depot failed") end
		end)
	end
end

--- Once per session, after loading: vehicles still on their way to a depot to be sold on arrival
-- (sent so by an earlier version of this mod or another mod) are sold right away with the game's
-- Sell, before the engine's sale on arrival can crash the game. Ones a mission protects stay as they
-- are. Returns how many were sold.
---@return integer
function actions.rescue()
	local sell = {} ---@type Engine.Entity[]
	local owned = { requireOwnedByPlayer = api.engine.util.getPlayer() }
	for _i, vehicle in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE, owned)) do
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
		if tv and tv.sellOnArrival == true and not is_protected(vehicle) then sell[#sell + 1] = vehicle end
	end
	if #sell > 0 then
		api.cmd.sendCommand(api.cmd.makeVehicleSellCmd(sell), function(_c, success)
			debugPrint(TAG, " ", #sell, " vehicles to be sold on arrival: ", success and "sold now" or "not sold")
		end)
	end
	return #sell
end

--- One more vehicle like the line's newest. Returns false if the line has no vehicle to copy.
---@param line Engine.Entity
---@param add_feedback? uo.actions.Feedback
---@return boolean
function actions.add_vehicle(line, add_feedback)
	return actions.clone_vehicle(line_vehicle(line, true), add_feedback)
end

--- Whether remove_vehicle would refuse because a mission protects the line's oldest vehicle. The
-- line window turns the button's sound off then, as the vehicle window does for "Sell".
---@param line Engine.Entity
---@param protected? uo.actions.Protected
---@return boolean
function actions.remove_refused(line, protected)
	local oldest = line_vehicle(line, false)
	return oldest ~= nil and is_protected(oldest, protected)
end

--- Retires the line's oldest vehicle (see retire_vehicle). Returns false if there is nothing to
-- retire or the oldest vehicle is protected.
---@param line Engine.Entity
---@param add_feedback? uo.actions.Feedback
---@param protected? uo.actions.Protected
---@return boolean
function actions.remove_vehicle(line, add_feedback, protected)
	return actions.retire_vehicle(line_vehicle(line, false), add_feedback, protected)
end

--- Event that runs an action by name; param { name, entity }.
actions.ACTION_EVENT = "uio.action"

local BY_NAME = { "add_vehicle", "remove_vehicle", "clone_vehicle", "retire_vehicle", "open_entity",
	"open_line_manager" }

--- Runs the action `param.name` on `param.entity`; logs and ignores unknown names. There is no
-- window here: feedback goes to the log, and protection comes from the copy kept from the event.
---@param param? { name: string?, entity: Engine.Entity? }
function actions.run(param)
	param = param or {}
	for _i, name in ipairs(BY_NAME) do
		if name == param.name then
			local ok = actions[name](param.entity) ---@type boolean? nil from open_entity/open_line_manager
			debugPrint(TAG, " action ", name, " ", tostring(param.entity), " -> ", tostring(ok ~= false))
			return
		end
	end
	log_feedback("unknown action " .. tostring(param.name))
end

--- The protected entities for a caller without a gameCtx, e.g. the testbench's debug events.
---@return uo.actions.Protected
function actions.protected_entities()
	return protected_entities
end

return actions
