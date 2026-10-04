--- The line window's "Vehicles" card with two vanilla action buttons under the vehicle table:
-- "Add Vehicle" (clone the line's newest vehicle onto the line) and "Remove Vehicle" (send the
-- oldest to a depot and sell it there). Adding or removing a vehicle no longer needs the Line
-- Manager or the vehicle store. Like the vehicle window, the card lists under its buttons why the
-- game refused (no money, mission lock, protected vehicle, no depot). Each vehicle row also shows
-- its load and a condition icon between the name and the vehicle icon; their tooltip names the
-- next stop, speed, load, condition and delivery quality (vehicle_info.lua).
-- Replaces the exported base plugin recipe line_eow.LineVehiclesPlugin (react-replacement-config,
-- see line_vehicles.script.lua). The vehicle table is a copy of the base one, registered under the
-- base recipe names so the base stylesheet applies unchanged. If the card fails, the base card is
-- shown for the rest of the session (fallback.lua).
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
local feedback_list_util = require("::/gui/line_vehicle_mgmt/feedback_list_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local actions = require("/ui_overhaul/gui/actions.lua")
local vehicle_info = require("/ui_overhaul/gui/vehicle_info.lua")
local fallback = require("/ui_overhaul/gui/fallback.lua")

local line_vehicles = {}

--- Marked failed once the card failed: the base card is shown for the rest of the session.
line_vehicles.switch = fallback.switch("line vehicles card")

---@class uo.gui.line_vehicles.StatusParams: react.Param
---@field vehicle Engine.Entity

---@class uo.gui.line_vehicles.ContentParams: react.Param
---@field line Engine.Entity
---@field gameCtx game.gui.main.game_context.GameContext

local reported = {} ---@type table<string, boolean>
---@param key string
---@param err any the pcall error, any value
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] line vehicles card: ", key, " failed: ", tostring(err))
end

---@param children react.TreeNodeId[]
---@return react.TreeNodeId
local function horizontal(children)
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end

---@return integer
local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

-- The status cell's content; `info` from vehicle_info.read, or nil.
---@param info? uo.gui.vehicle_info.Info
---@return react.TreeNodeId
local function render_status(info)
	if not info then return horizontal{} end
	local ok, text = pcall(vehicle_info.tooltip, info, false)
	local tooltip = ok and text or nil
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
end

-- Load and condition of a vehicle, the five figures in the tooltip.
---@param params uo.gui.line_vehicles.StatusParams
---@return react.TreeNodeId
local Status = react.RegisterRecipe("UioLineVehicleStatus", function(params)
	local state = engine_react_util.useStepStateTimer(function()
		local ok, info = pcall(vehicle_info.read, params.vehicle)
		return ok and info or nil
	end, 1.0)
	local ok, node = pcall(render_status, state:old())
	if ok then return node end
	report("vehicle status", node)
	return horizontal{}
end)

-- Copy of base LineTableCellVehicle (line_eow.script.tl), same name for the base stylesheet; the
-- status sits between the name and the vehicle icon.
---@param params builtin.TableCellParam
---@return react.TreeNodeId
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
---@param params builtin.TableCellParam
---@return react.TreeNodeId
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
---@param line Engine.Entity
---@return react.TreeNodeId
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

---@param params uo.gui.line_vehicles.ContentParams
---@return react.TreeNodeId
local Content = react.RegisterRecipe("UioLineVehicles", function(params)
	local line, game_ctx = params.line, params.gameCtx
	-- The base handlers report why they did not act (money, mission, depot) through addFeedback; the
	-- vehicle window shows that in a feedback list under its action buttons (vehicle.tl), and so does
	-- this card.
	---@type react.RefWrapApi<game.gui.line_vehicle_mgmt.feedback_list_util.FeedBackViewerAPI>
	local feedback_ref = react.useNodeRef(feedback_list_util.FeedbackList)
	---@type uo.actions.Feedback
	local function add_feedback(message, mode, dialog_data, id)
		if not feedback_ref:hasExpired() and feedback_ref:get() then
			feedback_ref:get():getApi().addFeedback(message, mode, dialog_data, nil, id, true)
		end
	end
	---@return uo.actions.Protected?
	local function protected_entities()
		local filters = game_ctx and game_ctx.filters and game_ctx.filters:get()
		return filters and filters.protectedEntities
	end
	-- The vehicle window's "Sell" has no sound while the vehicle is protected (vehicle.tl:535); the
	-- refused click shows the reason instead. Read on a timer, since filters is a ref and a mission's
	-- change alone does not render the card again.
	local refused = engine_react_util.useStepStateTimer(function()
		local ok, result = pcall(function() return actions.remove_refused(line, protected_entities()) end)
		if ok then return result end
		report("protected vehicles", result)
		return false
	end)
	local function add() actions.add_vehicle(line, add_feedback) end
	local function remove() actions.remove_vehicle(line, add_feedback, protected_entities()) end
	-- testbench: what the two buttons do, for a line window showing `param.line`
	react.onEvent("uio.debug.line_vehicles", function(_e, param)
		if type(param) ~= "table" or param.line ~= line then return end
		if param.action == "add" then add() elseif param.action == "remove" then remove() end
	end)
	local ok, node = pcall(function()
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = {
			Table(line),
			entity_window_util.ActionButtonBar{
				primaryButtons = {
					{
						description = _("Add Vehicle"),
						icon = "::/gui/entity_window/icons/symbol_square_copy.tga",
						onClick = add,
						sound = "Buy",
						tag = "uio.line.add_vehicle",
					},
					{
						description = _("Remove Vehicle"),
						icon = "::/gui/entity_window/icons/building_depot_arrow.tga",
						onClick = remove,
						sound = not refused:old() and "SendToDepot" or nil,
						tag = "uio.line.remove_vehicle",
					},
				},
			},
			feedback_list_util.FeedbackList(react.ref(feedback_ref), {}),
		} }
	end)
	if ok then return node end
	-- after its hooks, so the card declares the same ones; the parent shows the base card from now on
	fallback.fail(line_vehicles.switch, node)
	return builtin.BoxLayout{}
end)

---@param params game.gui.entity_window.line.line_eow.script.LineWidgetPluginParams
---@return react.TreeNodeId
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

-- The card's hooks are in its content recipe; this one declares fallback.use_base's two, always.
---@param params game.gui.entity_window.line.line_eow.script.LineWidgetPluginParams
---@return react.TreeNodeId
local Replacement = react.RegisterRecipe("LineVehiclesPlugin", function(params)
	local use_base = fallback.use_base(line_vehicles.switch)
	if not use_base and params.ownershipState == "Player" then
		local ok, node = pcall(render, params)
		if ok then return node end
		fallback.fail(line_vehicles.switch, node)
	end
	return builtin.BoxLayout{ children = { react.CallOriginalRecipe(line_eow.LineVehiclesPlugin, params) } }
end)

--- Called from the react-replacement-config before the UI starts.
---@param replacement_api react.ReplacementApi
function line_vehicles.install(replacement_api)
	replacement_api.ReplaceRecipe(line_eow.LineVehiclesPlugin, Replacement)
end

return line_vehicles
