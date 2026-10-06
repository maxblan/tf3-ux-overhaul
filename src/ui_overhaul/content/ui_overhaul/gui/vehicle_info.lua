--- What a vehicle is doing, in five figures: load, speed (or why it is not moving), destination,
-- condition and delivery quality (passenger happiness, cargo on time). Shared by the map tooltip
-- (vehicle_tooltip.lua), the Line Manager's vehicle rows (lvm_rows.lua) and the line window's
-- Vehicles card (line_vehicles.lua), so they all say the same thing in the same words.
--
-- `read` only reads the engine (it runs in timer callbacks); `lines` and `summary` translate and
-- format (GUI thread, while rendering). Texts are the game's own where it has them: the vehicle
-- window's state messages, condition levels and quality labels.
-- @module ui_overhaul.gui.vehicle_info
local cargo_util = require("::/gui/main/cargo_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local vehicle_util = require("::/gui/line_vehicle_mgmt/vehicle_util.tl")

local vehicle_info = {}

---@alias uo.gui.vehicle_info.State "en_route"|"at_terminal"|"to_depot"|"in_depot"

---What `read` found out about a vehicle.
---@class uo.gui.vehicle_info.Info
---@field speed number
---@field stopped boolean
---@field noPath boolean
---@field load integer
---@field capacity integer
---@field state uo.gui.vehicle_info.State
---@field lineName? string en route or at a terminal
---@field destination? string the next stop's or the depot's name
---@field stop? integer 1-based index of the next stop, with `destination` on a line
---@field stops? integer
---@field waitingForPath? boolean
---@field condition number
---@field happiness? number
---@field onTime? number

--- The vehicle a hovered entity belongs to (a carriage delegates to its train), or nil.
---@param entity? Engine.Entity
---@return Engine.Entity?
function vehicle_info.owning_vehicle(entity)
	if not entity or entity < 0 or not api.engine.entityExists(entity) then return nil end
	if api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_VEHICLE) then return entity end
	if api.engine.getComponent(entity, api.type.ComponentType.CARRIAGE) then
		local info = api.engine.system.carriageListSystem.getVehicleInfo(entity)
		local owner = info and info.owningVehicle
		if owner and owner >= 0 and api.engine.getComponent(owner, api.type.ComponentType.TRANSPORT_VEHICLE) then
			return owner
		end
	end
	return nil
end

---@param vehicle Engine.Entity
---@param cargo_type? CargoTypeId
---@return number?
local function quality(vehicle, cargo_type)
	local data = api.engine.util.cargo.getCargoQualityDataForVehicle(vehicle, cargo_type)
	if data and data.countTotal and data.countTotal > 0 then return data.averageQuality end
	return nil
end

--- Plain facts about `vehicle`, or nil. Engine reads only.
---@param vehicle Engine.Entity
---@return uo.gui.vehicle_info.Info?
function vehicle_info.read(vehicle)
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	if not tv then return nil end
	local states = api.type.enum.TransportVehicleState
	local on_line = tv.state == states.EN_ROUTE or tv.state == states.AT_TERMINAL
	---@type uo.gui.vehicle_info.Info
	local info = {
		speed = api.engine.util.vehicle.getSpeed(vehicle) or 0,
		stopped = tv.userStopped or false,
		noPath = tv.noPath or false,
		load = 0,
		capacity = 0,
		state = on_line and (tv.state == states.AT_TERMINAL and "at_terminal" or "en_route")
			or (tv.state == states.GOING_TO_DEPOT and "to_depot" or "in_depot"),
		condition = vehicle_util.getAvgMaintenanceState(vehicle),
	}
	if on_line then
		local line = api.engine.getComponent(tv.line, api.type.ComponentType.LINE)
		info.lineName = api.engine.util.getEntityName(tv.line)
		if line and tv.stopIndex >= 0 and tv.stopIndex < #line.stops then
			info.destination = api.engine.util.getEntityName(line.stops[tv.stopIndex + 1].stationGroup)
			info.stop = tv.stopIndex + 1
			info.stops = #line.stops
		end
		if info.state == "en_route" and not info.stopped and not info.noPath then
			info.waitingForPath = api.engine.system.landVehicleMoveSystem.isTrainWaitingForFreePath(vehicle) or false
		end
	elseif tv.depot and tv.depot >= 0 then
		info.destination = api.engine.util.getEntityName(tv.depot)
	end
	-- { cargo type, fill, capacity } per cargo type: the one exported function that counts the fill
	-- (calculateSortedVehicleCargoInfo leaves `fill` nil, so the load always read 0)
	for _i, cargo in ipairs(cargo_util.calculateSortedVehicleCargoInfoCompareValue(vehicle) or {}) do
		info.load = info.load + (cargo[2] or 0)
		info.capacity = info.capacity + (cargo[3] or 0)
	end
	info.happiness = quality(vehicle, cargo_util.getPassengerCargoTypeId())
	info.onTime = quality(vehicle)
	return info
end

--- Load as a fraction of the capacity, or nil without capacity.
---@param info? uo.gui.vehicle_info.Info
---@return number?
function vehicle_info.load_fraction(info)
	if not info or info.capacity <= 0 then return nil end
	return info.load / info.capacity
end

--- What the vehicle is doing right now, as the vehicle window says it (GUI thread).
---@param info uo.gui.vehicle_info.Info
---@return string
function vehicle_info.motion_text(info)
	if info.stopped then return info.speed > 0 and _("Stopping") or _("Stopped") end
	if info.state == "in_depot" then return _("In Depot") end
	if info.noPath then return _("No Path") end
	if info.waitingForPath then return _("Waiting for Free Path") end
	if info.state == "at_terminal" then return _("At Terminal") end
	return api.util.formatSpeed(info.speed)
end

---@param v number
---@return string
local function percent(v) return api.util.toStringPercentPrecision(v, 0) end

--- The five figures as tooltip lines (GUI thread).
---@param info? uo.gui.vehicle_info.Info
---@return string[]
function vehicle_info.lines(info)
	if not info then return {} end
	local lines = {} ---@type string[]
	local destination = info.destination
	if info.state == "to_depot" or info.state == "in_depot" then
		lines[#lines + 1] = info.state == "to_depot"
			and (destination and (_("Going to Depot") .. ": " .. destination) or _("Going to Depot"))
			or (destination and (_("In Depot") .. ": " .. destination) or _("In Depot"))
	elseif destination then
		lines[#lines + 1] = lang_util.format(_("Next stop: {station} ({index} of {count})"),
			{ station = destination, index = info.stop, count = info.stops })
	end
	lines[#lines + 1] = lang_util.format(_("Speed: {value}"), { value = vehicle_info.motion_text(info) })
	local fraction = vehicle_info.load_fraction(info)
	if fraction then
		lines[#lines + 1] = lang_util.format(_("Load: {load} of {capacity} ({percent})"), {
			load = lang_util.formatInt(info.load), capacity = lang_util.formatInt(info.capacity), percent = percent(fraction),
		})
	end
	if info.condition then
		lines[#lines + 1] = lang_util.format(_("Condition: {level} ({percent})"),
			{ level = vehicle_util.getConditionText(info.condition), percent = percent(info.condition) })
	end
	if info.happiness then
		lines[#lines + 1] = lang_util.format(_("Average Happiness: {amount}"), { amount = percent(info.happiness) })
	end
	if info.onTime then
		lines[#lines + 1] = lang_util.format(_("Average Remaining Delivery Time: {amount}"),
			{ amount = percent(info.onTime) })
	end
	return lines
end

--- The line name, then the five figures, as one tooltip text (GUI thread).
---@param info? uo.gui.vehicle_info.Info
---@param with_line? boolean
---@return string
function vehicle_info.tooltip(info, with_line)
	local lines = vehicle_info.lines(info)
	if with_line and info and info.lineName then table.insert(lines, 1, info.lineName) end
	return table.concat(lines, "\n")
end

return vehicle_info
