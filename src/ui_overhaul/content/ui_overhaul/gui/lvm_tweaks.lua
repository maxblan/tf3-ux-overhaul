--- Line Manager safety and memory (backlog D3):
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
-- The confirmation wraps react.fireEvent for "duplicateVehicles" (installed before the UI starts,
-- see lvm_tweaks.script.lua); the memory uses the tool stack's pop hook (tool_stack.lua) and the
-- entry point's per-frame step (entry.lua).
-- @module ui_overhaul.gui.lvm_tweaks
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local lang_util = require("::/scripts/lang_util.tl")
local vehicle_list_react_util = require("::/gui/line_vehicle_mgmt/vehicle_list_react_util.tl")
local vehicle_react_util = require("::/gui/line_vehicle_mgmt/vehicle_react_util.tl")
local tool_stack = require("/ui_overhaul/gui/tool_stack.lua")

local lvm_tweaks = {}

local last_line = nil -- line selected when the Line Manager was last closed
local reopen_line = nil -- line to select on the next step, after an untargeted open

-- Confirmation ------------------------------------------------------------------------------------

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
	local original_fire = react.fireEvent
	react.fireEvent = function(src, name, param, ...)
		if name == "duplicateVehicles" and type(param) == "table" and not param.uioConfirmed
			and type(param.addFeedback) == "function" and type(param.vehicleEntities) == "table"
			and #param.vehicleEntities > 1 then
			local ok, err = pcall(confirm_clone, original_fire, src, param)
			if ok then return end
			debugPrint("[ui_overhaul] clone confirmation failed, cloning directly: ", tostring(err))
		end
		return original_fire(src, name, param, ...)
	end
end

-- Common params of the open Line Manager -------------------------------------------------------------

-- The Line Manager rebuilds its "common params" (actions, prompts, selection state) on every render
-- and hands them to the exported VehicleList; the wrapper below keeps the latest and re-wraps newLine.
local current = nil
local wrapped_new_line = setmetatable({}, { __mode = "k" }) -- wrapper functions we created

local function selected_line_count(common)
	local ref = common.lineManagerStateRef
	local state = ref and ref:get()
	return state and state.lineListEntitiesSelected and #state.lineListEntitiesSelected or 0
end

local function wrap_new_line(common)
	local original = common.newLine
	if type(original) ~= "function" or wrapped_new_line[original] then return end
	local wrapper = function(station, vehicles, ...)
		if vehicles and #vehicles > 0 and selected_line_count(common) >= 2 then
			vehicles = {} -- the vehicles were selected by selecting lines, not deliberately
		end
		return original(station, vehicles, ...)
	end
	wrapped_new_line[wrapper] = true
	common.newLine = wrapper
end

local VehicleList = react.RegisterRecipe("VehicleList", function(params)
	local ok, err = pcall(function()
		if params and params.commonParams then
			current = params.commonParams
			wrap_new_line(params.commonParams)
		end
	end)
	if not ok then debugPrint("[ui_overhaul] Line Manager params not captured: ", tostring(err)) end
	return builtin.BoxLayout{ children = { react.CallOriginalRecipe(vehicle_list_react_util.VehicleList, params) } }
end)

-- Replace confirmation ----------------------------------------------------------------------------

local function replace_cost(changes)
	local cost = 0
	for _i, change in ipairs(changes) do
		for _j, part in ipairs(change.config.vehicles) do cost = cost + api.engine.util.vehicle.getPartPrice(part) end
		cost = cost - api.engine.util.vehicle.getDepreciatedValue(change.vehicleEntity)
	end
	return cost
end

local function patch_handle_vehicle_changes()
	local original = vehicle_react_util.HandleVehicleChanges
	vehicle_react_util.HandleVehicleChanges = function(changes, ...)
		local args = { ... }
		local replaces = 0
		for _i, change in ipairs(changes or {}) do
			if change.vehicleEntity >= 0 and #change.config.vehicles > 0 then replaces = replaces + 1 end
		end
		local ask = current and type(current.addFeedback) == "function"
		if replaces > 1 and ask then
			local ok = pcall(function()
				local cost = replace_cost(changes)
				local text = cost > 0
					and lang_util.format(_("Replace {count} vehicles for {cost}?"),
						{ count = replaces, cost = api.util.formatMoney(cost) })
					or lang_util.format(_("Replace {count} vehicles?"), { count = replaces })
				current.addFeedback(text, "Question", {
					onAccept = function() original(changes, table.unpack(args)) end,
					acceptText = _("Replace"),
				}, 2)
			end)
			if ok then return end
		end
		return original(changes, ...)
	end
end

-- Memory ------------------------------------------------------------------------------------------

local function remember_selection(entry)
	if entry.toolDef.name ~= "Manager" then return end
	local ref = entry.params and entry.params.lineManagerStateRef
	local state = ref and ref:get()
	local selected = state and state.lineListEntitiesSelected
	last_line = selected and selected[1] and selected[1].entity or nil
end

--- "openVehicleManager" handler of the entry point: an open without a target restores the selection
-- on the next step (after the base handler has reset it).
function lvm_tweaks.on_open(param)
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

--- Called from the react-replacement-config before the UI starts.
function lvm_tweaks.install(replacement_api)
	install_confirmation()
	patch_handle_vehicle_changes()
	table.insert(tool_stack.on_pop, remember_selection)
	replacement_api.ReplaceRecipe(vehicle_list_react_util.VehicleList, VehicleList)
end

return lvm_tweaks
