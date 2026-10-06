--- Line Manager safety and memory:
--   * with two or more lines selected, clicking a station creates the new line without moving all
--     their vehicles onto it (selecting lines selects their whole fleets); a deliberate vehicle
--     selection still moves the vehicles as before
--   * replacing or modifying more than one vehicle at once asks first, with the count and the net
--     cost, in the Line Manager's question prompt
--   * cloning more than one vehicle asks first, with the Line Manager's own question prompt (as it
--     already does before selling): clicking a line selects all its vehicles, so "Clone" used to
--     double the whole fleet without asking
--   * reopening the Line Manager without a target (game bar button, hotkey) selects the line that
--     was selected when it was closed, instead of starting empty
--   * the "Add stop at ..." hover says when vehicles could not get there: no path from the stop
--     before the insert position, or onward to the next stop (the engine's path search with the
--     line's transport modes), in the game's own words
--   * a row of the list's vehicle models above the vehicle list, and Shift+click on a vehicle row
--     to select its model (lvm_models.lua); a new line started from vehicles of two or more lines
--     starts empty, like one started with several lines selected
-- The confirmation wraps react.fireEvent for "duplicateVehicles" (installed before the UI starts,
-- see installer.lua); the memory uses the tool stack's pop hook (tool_stack.lua) and the
-- entry point's per-frame step (entry.lua).
-- @module ui_overhaul.gui.lvm_tweaks
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local lang_util = require("::/scripts/lang_util.tl")
local vehicle_list_react_util = require("::/gui/line_vehicle_mgmt/vehicle_list_react_util.tl")
local vehicle_react_util = require("::/gui/line_vehicle_mgmt/vehicle_react_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local manager_tooltips_util = require("::/gui/line_vehicle_mgmt/manager_tooltips_util.tl")
local tool_stack = require("/ui_overhaul/gui/tool_stack.lua")
local lvm_models = require("/ui_overhaul/gui/lvm_models.lua")
local line_problems = require("/ui_overhaul/core/line_problems.lua")
local table_util = require("::/scripts/table_util.tl")
local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")

-- The base recipes as the modules hold them while this mod loads, and safe calls of them (guard.base).
local base_vehicle_list = vehicle_list_react_util.VehicleList
local base_add_stop = manager_tooltips_util.LMAddStop
local original_list = guard.base("VehicleList", base_vehicle_list)
local original_add_stop = guard.base("LMAddStop", base_add_stop)

local lvm_tweaks = {}

---@alias uo.gui.lvm_tweaks.Common game.gui.line_vehicle_mgmt.line_util.CommonActionParams
---@alias uo.gui.lvm_tweaks.ListParams game.gui.line_vehicle_mgmt.vehicle_list_react_util.VehicleListParams
---@alias uo.gui.lvm_tweaks.Pick game.gui.line_vehicle_mgmt.line_util.StationSelectionDetails
---A function a wrapper replaces: the previous one in the chain (the game's, or another mod's wrapper
---around it), called with whatever the wrapper got and returning whatever it returns.
---@alias uo.gui.lvm_tweaks.Previous fun(...: any): any

---The "duplicateVehicles" param, marked once the player confirmed.
---@class uo.gui.lvm_tweaks.DuplicateParam: game.gui.line_vehicle_mgmt.manager_window.DuplicateVehiclesParam
---@field uioConfirmed? boolean

---The first missing path an added stop would create.
---@class uo.gui.lvm_tweaks.MissingPath
---@field origin Engine.Entity station group
---@field destination Engine.Entity station group

local last_line = nil ---@type Engine.Entity? line selected when the Line Manager was last closed
local reopen_line = nil ---@type Engine.Entity? line to select on the next step, after an untargeted open

-- Confirmation ------------------------------------------------------------------------------------

---@param original_fire uo.gui.lvm_tweaks.Previous
---@param src react.RefWrap?
---@param param uo.gui.lvm_tweaks.DuplicateParam
local function confirm_clone(original_fire, src, param)
	local count = #param.vehicleEntities
	local text = nGetText("Clone Selected Vehicle", "Clone Selected Vehicles", count)
	param.addFeedback(string.format("%s (%d)", text, count), "Question", {
		onAccept = function()
			param.uioConfirmed = true
			original_fire(src, "duplicateVehicles", param)
		end,
		acceptText = text,
	}, 2)
end

local function install_confirmation()
	-- many mods wrap react.fireEvent for their own events: generic, never a conflict
	priority.chain(react, "fireEvent",
	---@param original_fire uo.gui.lvm_tweaks.Previous
	---@return uo.gui.lvm_tweaks.Previous
	function(original_fire)
		---@param src react.RefWrap?
		---@param name string
		---@param param? any the event's payload, any value
		---@param ... any passed on unchanged to the previous function
		---@return any ... whatever the previous function returns
		return function(src, name, param, ...)
			if name == "duplicateVehicles" and type(param) == "table" and not param.uioConfirmed
				and type(param.addFeedback) == "function" and type(param.vehicleEntities) == "table"
				and #param.vehicleEntities > 1 then
				local ok, err = pcall(confirm_clone, original_fire, src, param)
				if ok then return end
				debugPrint("[ui_overhaul] clone confirmation failed, cloning directly: ", tostring(err))
			end
			return original_fire(src, name, param, ...)
		end
	end, true)
end

-- Common params of the open Line Manager -------------------------------------------------------------

-- The Line Manager rebuilds its "common params" (actions, prompts, selection state) on every render
-- and hands them to the exported VehicleList; the wrapper below keeps the latest and re-wraps newLine.
local current = nil ---@type uo.gui.lvm_tweaks.Common?
---@type table<function, boolean>
local wrapped_new_line = setmetatable({}, { __mode = "k" }) -- wrapper functions we created

---@param common uo.gui.lvm_tweaks.Common
---@return integer
local function selected_line_count(common)
	local ref = common.lineManagerStateRef
	local state = ref and ref:get()
	return state and state.lineListEntitiesSelected and #state.lineListEntitiesSelected or 0
end

---@param vehicles Engine.Entity[]
---@return boolean
local function vehicles_from_several_lines(vehicles)
	local ok, count = pcall(lvm_models.line_count, vehicles, 2)
	return ok and count >= 2
end

---@param common uo.gui.lvm_tweaks.Common
local function wrap_new_line(common)
	local original = common.newLine ---@type uo.gui.lvm_tweaks.Previous
	if type(original) ~= "function" or wrapped_new_line[original] then return end
	---@param station uo.gui.lvm_tweaks.Pick
	---@param vehicles Engine.Entity[]
	---@param ... any passed on unchanged to the previous function
	---@return any ... whatever the previous function returns
	local wrapper = function(station, vehicles, ...)
		if vehicles and #vehicles > 0
			and (selected_line_count(common) >= 2 or vehicles_from_several_lines(vehicles)) then
			vehicles = {} -- selected by selecting lines or a model across lines, not one line's vehicles
		end
		return original(station, vehicles, ...)
	end
	wrapped_new_line[wrapper] = true
	common.newLine = wrapper
end

-- Shift+click on a vehicle row selects its model. The rows' cells keep the userParam of the render
-- that created them (DataTable), so the click handler is one stable function reading the latest
-- parameters (lvm_models.live). The check box calls the manager's selectVehicles directly, so that
-- is wrapped too (also reached from the map and the HUD).
---@param entities Engine.Entity[]
---@return boolean
local function shift_select(entities)
	return #entities == 1 and lvm_models.shift_held() and lvm_models.select_same_model(entities[1])
end

---@param entity Engine.Entity
---@param ... any passed on unchanged to the list's handler
---@return any ... whatever the list's handler returns
local function on_click_select_vehicle(entity, ...)
	local ok, done = pcall(shift_select, { entity })
	if ok and done then return end
	if not ok then debugPrint("[ui_overhaul] Shift+click model selection failed: ", tostring(done)) end
	local params = lvm_models.live.params
	local handler = params and params.onClickSelectVehicle ---@type uo.gui.lvm_tweaks.Previous?
	if type(handler) == "function" then return handler(entity, ...) end
end

---@type table<function, boolean>
local wrapped_select = setmetatable({}, { __mode = "k" }) -- selectVehicles wrappers we created

---@param params uo.gui.lvm_tweaks.ListParams
local function wrap_select_vehicles(params)
	local manager = params.managerRef and params.managerRef:get()
	local vm_api = manager and manager:getApi()
	local original = type(vm_api) == "table" and vm_api.selectVehicles ---@type uo.gui.lvm_tweaks.Previous|false|nil
	if type(original) ~= "function" or wrapped_select[original] then return end
	---@param entities Engine.Entity[]
	---@param selected boolean
	---@param ... any passed on unchanged to the previous function
	---@return any ... whatever the previous function returns
	local wrapper = function(entities, selected, ...)
		-- only a selection grows to the model; a deselection (Shift held or not) stays one vehicle
		if selected ~= false then
			local ok, done = pcall(shift_select, entities or {})
			if ok and done then return end
		end
		return original(entities, selected, ...)
	end
	wrapped_select[wrapper] = true
	vm_api.selectVehicles = wrapper
end

--- The list's parameters with the stable click handler and a local key that keeps the list's
-- identity while the model row comes and goes.
---@param params uo.gui.lvm_tweaks.ListParams
---@return uo.gui.lvm_tweaks.ListParams
local function list_params(params)
	local copy = table_util.shallowCopy(params)
	copy.onClickSelectVehicle = on_click_select_vehicle
	copy.meta = { localKey = "uio-lvm-list" }
	return copy
end

---@param params uo.gui.lvm_tweaks.ListParams
---@return react.TreeNodeId
local VehicleList = react.RegisterRecipe("VehicleList", function(params)
	react.onEvent("uio.debug.lvm_models", function(_e, param)
		local ok, err = pcall(lvm_models.debug, param)
		if not ok then debugPrint("[ui_overhaul] lvm models debug failed: ", tostring(err)) end
	end)
	-- the Line Manager focuses this recipe through its vehicleListRef (gamepad): focus goes on to the
	-- list, not to the model row above it
	local list_ref = react.useNodeRef()
	react.setPreferredFocusChild(list_ref)
	-- a closed Line Manager's params must not take questions (the replace confirmation, below)
	local captured = params and params.commonParams
	react.onUnmount(function()
		if captured ~= nil and current == captured then current = nil end
	end)
	local row, original_params = nil, params ---@type react.TreeNodeId?, uo.gui.lvm_tweaks.ListParams
	local ok, err = pcall(function()
		if params and params.commonParams then
			current = params.commonParams
			wrap_new_line(params.commonParams)
		end
	end)
	if not ok then debugPrint("[ui_overhaul] Line Manager params not captured: ", tostring(err)) end
	ok, err = pcall(function()
		if not (params and params.commonParams and params.commonParams.vehicleManagerStateRef) then return end
		original_params = list_params(params)
		pcall(wrap_select_vehicles, params)
		row = lvm_models.update(params)
	end)
	if not ok then debugPrint("[ui_overhaul] Line Manager models failed: ", tostring(err)) end
	local list = original_list.node(react.ref(list_ref), original_params)
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical,
		children = row and { row, list } or { list } }
end)

-- Replace confirmation ----------------------------------------------------------------------------

---@param changes game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleChange[]
---@return integer
local function replace_cost(changes)
	local cost = 0
	for _i, change in ipairs(changes) do
		-- per change: LuaLS cannot infer a sum updated in both an inner and an outer loop
		local price = 0
		for _j, part in ipairs(change.config.vehicles) do price = price + api.engine.util.vehicle.getPartPrice(part) end
		cost = cost + price - api.engine.util.vehicle.getDepreciatedValue(change.vehicleEntity)
	end
	return cost
end

local function patch_handle_vehicle_changes()
	priority.chain(vehicle_react_util, "HandleVehicleChanges",
	---@param original uo.gui.lvm_tweaks.Previous
	---@return uo.gui.lvm_tweaks.Previous
	function(original)
		---@param changes game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleChange[]
		---@param ... any passed on unchanged to the previous function
		---@return any ... whatever the previous function returns
		return function(changes, ...)
			local args = table.pack(...) -- may hold nils (getFirstStopToSendTo without a line context)
			local replaces = 0
			for _i, change in ipairs(changes or {}) do
				if change.vehicleEntity >= 0 and #change.config.vehicles > 0 then replaces = replaces + 1 end
			end
			local common = current
			if replaces > 1 and common and type(common.addFeedback) == "function" then
				local ok = pcall(function()
					local cost = replace_cost(changes)
					local text = cost > 0
						and lang_util.format(_("Replace {count} vehicles for {cost}?"),
							{ count = replaces, cost = api.util.formatMoney(cost) })
						or lang_util.format(_("Replace {count} vehicles?"), { count = replaces })
					common.addFeedback(text, "Question", {
						onAccept = function() original(changes, table.unpack(args, 1, args.n)) end,
						acceptText = _("Replace"),
					}, 2)
				end)
				if ok then return end
			end
			return original(changes, ...)
		end
	end)
end

-- Add-stop hover ----------------------------------------------------------------------------------

-- Vehicle nodes of the terminals of a stop: one terminal, one station or the whole group.
---@param station_group Engine.Entity
---@param station_index1? integer
---@param terminal_index1? integer
---@return NodeId[]
local function terminal_nodes(station_group, station_index1, terminal_index1)
	local group = api.engine.getComponent(station_group, api.type.ComponentType.STATION_GROUP)
	local nodes = {} ---@type NodeId[]
	for s, station_entity in ipairs(group and group.stations or {}) do
		if not station_index1 or station_index1 < 1 or s == station_index1 then
			local station = api.engine.getComponent(station_entity, api.type.ComponentType.STATION)
			---@cast station -nil -- a station group's stations are stations (line_manager_panel.tl:134 alike)
			for t, terminal in ipairs(station.terminals) do
				if not terminal_index1 or terminal_index1 < 1 or t == terminal_index1 then
					nodes[#nodes + 1] = terminal.vehicleNodeId
				end
			end
		end
	end
	return nodes
end

---@param via game.gui.line_vehicle_mgmt.line.ReactVia
---@return NodeId[]
local function via_nodes(via)
	return terminal_nodes(via.stop.stationGroup, via.stop.station1, via.stop.terminal1)
end

---@type { key: string?, value: (uo.gui.lvm_tweaks.MissingPath|false)? }
local reach_cache = { key = nil, value = nil }

--- { origin, destination } (station group entities) of the first missing path that adding `pick`
-- would create, or false. Cached per hovered stop, as the hover re-renders every frame.
---@param pick? uo.gui.lvm_tweaks.Pick
---@return uo.gui.lvm_tweaks.MissingPath|false
local function missing_path(pick)
	local common = current
	local line_state = common and common.lineState and common.lineState:old()
	if not (common and line_state and line_state.entityAndRevision and pick and pick.stationGroup) then return false end
	local line = line_state.entityAndRevision.entity
	local mode = common.getModeState and common.getModeState() or {}
	local insert_at = mode[1] == "SEGMENT" and mode[2] or nil
	local key = table.concat({ line, #line_state.path, pick.stationGroup, pick.stationIndex1 or 0,
		pick.terminalIndex1 or 0, tostring(insert_at) }, ":")
	if reach_cache.key == key then return reach_cache.value end
	local value = false ---@type uo.gui.lvm_tweaks.MissingPath|false
	local modes = {} ---@type TransportMode[]
	for transport_mode, on in pairs(api.engine.util.line.getLineTransportModesUnion(line) or {}) do
		if on then modes[#modes + 1] = transport_mode end
	end
	local before, after = line_problems.neighbours(line_state.path, insert_at)
	if #modes > 0 and before then
		local here = terminal_nodes(pick.stationGroup, pick.stationIndex1, pick.terminalIndex1)
		local find = api.engine.util.pathfinding.findPathNodeToNode
		if before.stop.stationGroup ~= pick.stationGroup and #find(via_nodes(before), here, modes) == 0 then
			value = { origin = before.stop.stationGroup, destination = pick.stationGroup }
		elseif after and after.stop.stationGroup ~= pick.stationGroup and #find(here, via_nodes(after), modes) == 0 then
			value = { origin = pick.stationGroup, destination = after.stop.stationGroup }
		end
	end
	reach_cache.key, reach_cache.value = key, value
	return value
end

---@param entity Engine.Entity
---@return string
local function entity_name(entity)
	return api.engine.util.getEntityName(entity) or _("Station")
end

-- Base text of the hover (manager_tooltips_util.tl, LMAddStop).
---@param pick uo.gui.lvm_tweaks.Pick
---@return string
local function add_stop_text(pick)
	if pick.flatStationTerminalIndex1 ~= nil then
		return lang_util.format(_("Add stop at {name} terminal {index}."), {
			name = entity_name(pick.stationGroup), index = lang_util.formatInt(pick.flatStationTerminalIndex1),
		})
	end
	return lang_util.format(_("Add stop at {name}."), { name = entity_name(pick.stationGroup) })
end

---@param pick uo.gui.lvm_tweaks.Pick
---@return react.TreeNodeId
local AddStopTooltip = react.RegisterRecipe("LMAddStop", function(pick)
	local ok, text = pcall(function()
		local base = add_stop_text(pick)
		local missing = missing_path(pick)
		if not missing then return base end
		return base .. "\n" .. lang_util.format(_("No path from {origin} to {destination} exists."), {
			origin = entity_name(missing.origin), destination = entity_name(missing.destination),
		})
	end)
	if ok then return line_react_util.makeTooltip(text) end
	debugPrint("[ui_overhaul] add-stop hover failed: ", tostring(text))
	return original_add_stop.layout(pick)
end)

-- Memory ------------------------------------------------------------------------------------------

---@param entry { toolDef: builtin.ToolDefinition, params?: game.gui.line_vehicle_mgmt.manager_window.ManagerToolParam }
local function remember_selection(entry)
	if entry.toolDef.name ~= "Manager" then return end
	local ref = entry.params and entry.params.lineManagerStateRef
	local state = ref and ref:get()
	local selected = state and state.lineListEntitiesSelected
	last_line = selected and selected[1] and selected[1].entity or nil
end

--- "openVehicleManager" handler of the entry point: an open without a target restores the selection
-- on the next step (after the base handler has reset it).
---@param param? game.gui.line_vehicle_mgmt.manager_window.ManagerWindowEventParam
function lvm_tweaks.on_open(param)
	-- the Line Manager feature switched off or given up to a mod that comes first (priority.lua)
	if not priority.active("line_manager") then return end
	param = param or {}
	if param.openWithLineEntity or param.openWithVehicleEntities or param.openWithDepotEntity or param.sendToLineMode then
		return
	end
	if last_line and api.engine.entityExists(last_line) then reopen_line = last_line end
end

--- Per-frame step of the entry point.
function lvm_tweaks.step()
	if not reopen_line then return end
	local line = reopen_line
	reopen_line = nil
	if api.engine.entityExists(line) then react.fireEvent(nil, "openVehicleManager", { openWithLineEntity = line }) end
end

--- Called by installer.lua before the UI starts.
---@param replacement_api react.ReplacementApi
function lvm_tweaks.install(replacement_api)
	install_confirmation()
	patch_handle_vehicle_changes()
	table.insert(tool_stack.on_pop, remember_selection)
	replacement_api.ReplaceRecipe(base_vehicle_list, VehicleList)
	replacement_api.ReplaceRecipe(base_add_stop, AddStopTooltip)
end

return lvm_tweaks
