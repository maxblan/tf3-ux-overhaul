--- Player actions behind the mod's buttons. Wherever possible they go through the base game's own
-- events, so the base checks (mission locks, money, depots) apply. GUI thread only.
-- API references: docs/api_cookbook.md §6.
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

---@param vehicle Engine.Entity
---@return number
local function purchase_time(vehicle)
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	local oldest ---@type number?
	for _i, part in ipairs(tv and tv.transportVehicleConfig.vehicles or {}) do
		if oldest == nil or part.purchaseTime < oldest then oldest = part.purchaseTime end
	end
	return oldest or 0
end

--- The line's newest (`newest` = true) or oldest vehicle, or nil.
---@param line Engine.Entity
---@param newest boolean
---@return Engine.Entity?
local function line_vehicle(line, newest)
	local best ---@type Engine.Entity?
	local best_time ---@type number?
	for _i, vehicle in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
		local t = purchase_time(vehicle)
		if best == nil or (newest and t > best_time) or (not newest and t < best_time) then
			best, best_time = vehicle, t
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

--- Sends the vehicle to a depot, where it is sold on arrival. A vehicle a mission protects is not
-- sold, as the vehicle window's "Sell" refuses it (vehicle.tl): `protected` is
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
	api.cmd.sendCommand(api.cmd.makeVehicleSendToDepotCmd(vehicle, true), function(_c, success)
		if not success then add_feedback(_("Vehicle could not be sent to depot."), nil, nil, nil) end
	end)
	return true
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
