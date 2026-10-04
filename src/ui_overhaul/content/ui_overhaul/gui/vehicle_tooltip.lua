--- Hovering a vehicle on the map shows, under its name, what it is doing: line, next stop, speed,
-- load, condition and delivery quality (vehicle_info.lua). Hovering a carriage shows its train.
-- Replaces the exported recipe game_tooltips.DefaultEntityToolTip and calls the original first, so
-- the name and the notification lines stay the game's. Other entities look exactly as before.
-- Installed by vehicle_tooltip.script.lua; if the block fails, the base tooltip stays.
-- @module ui_overhaul.gui.vehicle_tooltip
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local game_tooltips = require("::/gui/main/game_tooltips.tl")
local react = require("::/gui/main/react.lua")
local vehicle_info = require("/ui_overhaul/gui/vehicle_info.lua")

local vehicle_tooltip = {}

local REFRESH = 0.25 -- seconds: speed and load change while the player looks

local reported = {}
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] vehicle tooltip: ", key, ": ", tostring(err))
end

local function read(param)
	local entity = param.entityRef and param.entityRef:get()
	if param.filter and not param.filter(entity) then return nil end
	local vehicle = vehicle_info.owning_vehicle(entity)
	return vehicle and vehicle_info.read(vehicle) or nil
end

local VehicleBlock = react.RegisterRecipe("UioVehicleTooltip", function(param)
	react.setMouseTransparent(true)
	local state = engine_react_util.useStepStateTimer(function()
		local ok, info = pcall(read, param)
		if ok then return info end
		report("read", info)
		return nil
	end, REFRESH)
	local info = state:old()
	if not info then return builtin.BoxLayout{} end
	local ok, text = pcall(vehicle_info.tooltip, info, true)
	if not ok then
		report("text", text)
		return builtin.BoxLayout{}
	end
	return builtin.BoxLayout{ children = {
		builtin.TextView{
			meta = { class = "font-scale-tooltip, uio-vehicle-tooltip", mouseTransparent = true },
			text = text,
		},
	} }
end)

local Tooltip = react.RegisterRecipe("DefaultEntityToolTip", function(param)
	react.setMouseTransparent(true)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			react.CallOriginalRecipe(game_tooltips.DefaultEntityToolTip, param),
			VehicleBlock{ entityRef = param.entityRef, filter = param.filter },
		},
	}
end)

--- Called from the react-replacement-config before the UI starts.
function vehicle_tooltip.install(replacement_api)
	replacement_api.ReplaceRecipe(game_tooltips.DefaultEntityToolTip, Tooltip)
	debugPrint("[ui_overhaul] vehicle tooltip installed")
end

vehicle_tooltip.VehicleBlock = VehicleBlock -- for the testbench

return vehicle_tooltip
