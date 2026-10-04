--- The line window's "Vehicles" card with two vanilla action buttons under the vehicle table:
-- "Add Vehicle" (clone the line's newest vehicle onto the line) and "Remove Vehicle" (send the
-- oldest to a depot and sell it there). Adding or removing a vehicle no longer needs the Line
-- Manager or the vehicle store. Each vehicle row also shows its load and a condition icon between
-- the name and the vehicle icon; their tooltip names the next stop, speed, load, condition and
-- delivery quality (vehicle_info.lua).
-- Replaces the exported base plugin recipe line_eow.LineVehiclesPlugin (react-replacement-config,
-- see line_vehicles.script.lua). The vehicle table is a copy of the base one, registered under the
-- base recipe names so the base stylesheet applies unchanged. If rendering fails, the base card is
-- shown instead.
-- @module ui_overhaul.gui.line_vehicles
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local content_card = require("::/gui/main/content_card.tl")
local entity_window_util = require("::/gui/entity_window/entity_window_util.tl")
local line_eow = require("::/gui/entity_window/line/line_eow.script.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local vehicle_react_util = require("::/gui/line_vehicle_mgmt/vehicle_react_util.tl")
local vehicle_util = require("::/gui/line_vehicle_mgmt/vehicle_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local actions = require("/ui_overhaul/gui/actions.lua")
local vehicle_info = require("/ui_overhaul/gui/vehicle_info.lua")

local line_vehicles = {}

local function horizontal(children)
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end

local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

-- Load and condition of a vehicle, the five figures in the tooltip.
local Status = react.RegisterRecipe("UioLineVehicleStatus", function(params)
	local state = engine_react_util.useStepStateTimer(function()
		local ok, info = pcall(vehicle_info.read, params.vehicle)
		return ok and info or nil
	end, 1.0)
	local info = state:old()
	if not info then return horizontal{} end
	local ok, tooltip = pcall(vehicle_info.tooltip, info, false)
	tooltip = ok and tooltip or nil
	local fraction = vehicle_info.load_fraction(info)
	return builtin.BoxLayout{
		meta = { class = "uio-line-vehicle-status" },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.TextView{
				meta = { class = "font-scale-body, uio-line-vehicle-load", tooltip = tooltip },
				text = fraction and api.util.toStringPercentPrecision(fraction, 0) or "",
			},
			info.condition and builtin.ImageView{
				meta = { class = "uio-line-vehicle-condition", tooltip = tooltip },
				path = vehicle_util.getConditionIcon(info.condition),
				scaling = builtin.type.ImageViewScaling.AutoFit,
			} or nil,
		},
	}
end)

-- Copy of base LineTableCellVehicle (line_eow.script.tl), same name for the base stylesheet; the
-- status sits between the name and the vehicle icon.
local CellVehicle = react.RegisterRecipe("LineTableCellVehicle", function(params)
	return horizontal{
		line_react_util.NameTextView{
			entity = params.rowKey, locationButton = true, stackEntityOpen = true, editMode = false,
		},
		Status{ vehicle = params.rowKey },
		vehicle_react_util.VehicleWidget{ vehicleEntities = { params.rowKey } },
	}
end)

-- Copy of base LineTableCellAge; the tooltip shows the real share of the lifespan (the base rounds
-- it down to 0 % until the lifespan is reached).
local CellAge = react.RegisterRecipe("LineTableCellAge", function(params)
	local state = engine_react_util.useStepStateTimer(function()
		local tv = api.engine.getComponent(params.rowKey, api.type.ComponentType.TRANSPORT_VEHICLE)
		return tv and vehicle_util.getMinPurchaseTimeAndLifespan(tv) or nil
	end)
	local purchase_and_lifespan = state:old()
	local text, tooltip = _("Invalid"), nil
	if purchase_and_lifespan then
		local t = now()
		local purchase, lifespan = purchase_and_lifespan[1], purchase_and_lifespan[2]
		text = api.engine.util.formatAge(purchase, t)
		if t < purchase + lifespan then
			tooltip = lang_util.format(_("{total} of Lifetime ({age} Remaining)"), {
				total = api.util.toStringPercentPrecision((t - purchase) / lifespan, 0),
				age = api.engine.util.formatAge(t, purchase + lifespan),
			})
		else
			tooltip = _("Lifetime Reached")
		end
	end
	return horizontal{ builtin.TextView{ meta = { class = "font-scale-body", tooltip = tooltip }, text = text } }
end)

-- Copy of base LineVehiclesTable.
local Table = react.RegisterRecipe("LineVehiclesTable", function(line)
	local state = engine_react_util.useStepState(function()
		local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line)
		table.sort(vehicles)
		return vehicles
	end)
	return horizontal{
		builtin.DataTable{
			meta = { class = "line-vehicles-table" },
			columns = {
				builtin.ColumnDesc{ name = _("Vehicle"), recipe = CellVehicle, weight = 1,
					getCompareValue = function(v) return api.engine.util.getEntityName(v) or "" end },
				builtin.ColumnDesc{ name = _("Age"), recipe = CellAge, headerStyleClass = "age",
					getCompareValue = function(v)
						local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
						return tv and -vehicle_util.getMinPurchaseTimeAndLifespan(tv)[1] or 0
					end },
			},
			rowKeys = state:old(),
		},
	}
end)

local Content = react.RegisterRecipe("UioLineVehicles", function(params)
	local line, game_ctx = params.line, params.gameCtx
	local function protected(vehicle)
		local filters = game_ctx and game_ctx.filters and game_ctx.filters:get()
		return filters and filters.protectedEntities and filters.protectedEntities[vehicle]
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = {
		Table(line),
		entity_window_util.ActionButtonBar{
			primaryButtons = {
				{
					description = _("Add Vehicle"),
					icon = "::/gui/entity_window/icons/symbol_square_copy.tga",
					onClick = function() actions.add_vehicle(line) end,
					sound = "Buy",
					tag = "uio.line.add_vehicle",
				},
				{
					description = _("Remove Vehicle"),
					icon = "::/gui/entity_window/icons/building_depot_arrow.tga",
					onClick = function() actions.remove_vehicle(line, protected) end,
					sound = "SendToDepot",
					tag = "uio.line.remove_vehicle",
				},
			},
		},
	} }
end)

local function render(params)
	return builtin.BoxLayout{ children = {
		content_card.ContentCard{
			meta = { localKey = "lineVehicles" },
			title = _("Vehicles"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(Content,
				{ line = params.entityId, gameCtx = params.gameCtx }),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		},
	} }
end

local Replacement = react.RegisterRecipe("LineVehiclesPlugin", function(params)
	if params.ownershipState ~= "Player" then
		return builtin.BoxLayout{ children = { react.CallOriginalRecipe(line_eow.LineVehiclesPlugin, params) } }
	end
	local ok, node = pcall(render, params)
	if ok then return node end
	debugPrint("[ui_overhaul] line vehicles card failed, showing the base card: ", tostring(node))
	return builtin.BoxLayout{ children = { react.CallOriginalRecipe(line_eow.LineVehiclesPlugin, params) } }
end)

--- Called from the react-replacement-config before the UI starts.
function line_vehicles.install(replacement_api)
	replacement_api.ReplaceRecipe(line_eow.LineVehiclesPlugin, Replacement)
end

return line_vehicles
