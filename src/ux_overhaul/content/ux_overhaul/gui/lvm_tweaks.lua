--- Line Manager safety and memory (backlog D3):
--   * cloning more than one vehicle asks first, with the Line Manager's own question prompt (as it
--     already does before selling): clicking a line selects all its vehicles, and "Clone" then
--     silently doubled the whole fleet
--   * reopening the Line Manager without a target (game bar button, hotkey) selects the line that
--     was selected when it was closed, instead of starting empty
-- The confirmation wraps react.fireEvent for "duplicateVehicles" (installed before the UI starts,
-- see lvm_tweaks.script.lua); the memory uses the tool stack's pop hook (tool_stack.lua) and the
-- entry point's per-frame step (entry.lua).
-- @module ux_overhaul.gui.lvm_tweaks
local react = require("::/gui/main/react.lua")
local tool_stack = require("/ux_overhaul/gui/tool_stack.lua")

local lvm_tweaks = {}

local last_line = nil -- line selected when the Line Manager was last closed
local reopen_line = nil -- line to select on the next step, after an untargeted open

-- Confirmation ------------------------------------------------------------------------------------

local function confirm_clone(original_fire, src, param)
	local count = #param.vehicleEntities
	local text = nGetText("Clone Selected Vehicle", "Clone Selected Vehicles", count)
	param.addFeedback(string.format("%s (%d)", text, count), "Question", {
		onAccept = function()
			param.uxoConfirmed = true
			original_fire(src, "duplicateVehicles", param)
		end,
		acceptText = text,
	}, 2)
end

local function install_confirmation()
	local original_fire = react.fireEvent
	react.fireEvent = function(src, name, param, ...)
		if name == "duplicateVehicles" and type(param) == "table" and not param.uxoConfirmed
			and type(param.addFeedback) == "function" and type(param.vehicleEntities) == "table"
			and #param.vehicleEntities > 1 then
			local ok, err = pcall(confirm_clone, original_fire, src, param)
			if ok then return end
			debugPrint("[ux_overhaul] clone confirmation failed, cloning directly: ", tostring(err))
		end
		return original_fire(src, name, param, ...)
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
function lvm_tweaks.install(_replacement_api)
	install_confirmation()
	table.insert(tool_stack.on_pop, remember_selection)
end

return lvm_tweaks
