--- How a train or tram copes with slopes, where players decide about it:
--   * the vehicle window gets a Performance card: the game's rating (Poor to Excellent) and the
--     top speed on flat track and on medium and steep slopes, with the time and distance it takes
--     to reach it, fully loaded and empty
--   * in the vehicle store's composition (the cart), the Performance row's tooltip shows the same
--     slope speeds (the game computes them there and throws them away)
-- All figures come from the game's own vehicle_util.getPowerRatingTextAndToolTip, so they match the
-- rating the store shows. The card is a plugin of ::VehicleEowExtensionPoint (performance_card.res);
-- the cart tooltip wraps that function and builtin.TextView while the cart renders
-- (performance.res, react-replacement-config).
-- @module ui_overhaul.gui.performance
local builtin = require("::/gui/main/builtin.lua")
local content_card = require("::/gui/main/content_card.tl")
local lang_util = require("::/scripts/lang_util.tl")
local react = require("::/gui/main/react.lua")
local vehicle_store_util = require("::/gui/line_vehicle_mgmt/vehicle_store_util.tl")
local vehicle_util = require("::/gui/line_vehicle_mgmt/vehicle_util.tl")

local performance = {}

-- The slopes the game rates against (vehicle_util.tl: 0, 0.0375, 0.075).
local MEDIUM, HIGH = 0.0375, 0.075

local function text(value, class)
	return builtin.TextView{ meta = { class = class or "font-scale-body" }, text = value }
end

--- Rating and slope speeds of a consist of `model_ids` (with the vehicle's maintenance modifiers),
-- fully loaded and empty: { rating, loaded, empty } (texts), or nil for vehicles the game does not
-- rate (no power or tractive effort: ships, aircraft, wagons alone). GUI thread (texts).
function performance.ratings(model_ids, modifiers)
	local vehicles = {}
	for i, model_id in ipairs(model_ids or {}) do
		vehicles[i] = vehicle_store_util.makeSingleVehicle(api.res.modelRep.get(model_id))
	end
	if #vehicles == 0 then return nil end
	local data = vehicle_store_util.collectVehicleData(vehicles, modifiers)
	if not data or not (data.power > 0 and data.tractiveEffort > 0) then return nil end
	local loaded = vehicle_util.getPowerRatingTextAndToolTip(data.weight + data.weightMaxPayload, data.power,
		data.tractiveEffort, data.speed, data.rollingFriction)
	local empty = vehicle_util.getPowerRatingTextAndToolTip(data.weight, data.power, data.tractiveEffort, data.speed,
		data.rollingFriction)
	if not loaded then return nil end
	return { rating = loaded[1], loaded = loaded[2], empty = empty and empty[2] or nil }
end

-- What the game's slope names mean: "Medium slope: 3.8 %, high slope: 7.5 %".
local function slopes_text()
	return lang_util.format(_("Medium slope: {medium}, high slope: {high}"), {
		medium = api.util.toStringPercentPrecision(MEDIUM, 1),
		high = api.util.toStringPercentPrecision(HIGH, 1),
	})
end

local Card = react.RegisterRecipe("UioVehiclePerformance", function(params)
	local r = params.ratings
	-- fully loaded in the card (the case that limits a train); without load in the tooltip
	local tooltip = r.empty and (_("Without load") .. "\n" .. r.empty) or nil
	local children = {
		builtin.TextView{ meta = { class = "font-scale-headline", tooltip = tooltip },
			text = _("Performance") .. ": " .. r.rating .. " (" .. _("Fully loaded") .. ")" },
		builtin.TextView{ meta = { class = "font-scale-body", tooltip = tooltip }, text = r.loaded },
	}
	children[#children + 1] = text(slopes_text(), "font-scale-annotation")
	return builtin.BoxLayout{
		meta = { class = "uio-performance", id = "uio.vehicle.performance." .. tostring(params.entityId) },
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end)

--- Plugin recipe body of the vehicle window (guarded by performance.script.lua).
function performance.card(params)
	if params.ownershipState ~= "Player" then return builtin.BoxLayout{} end
	local info = params.state and params.state.staticVehicleInfo
	if not info then return builtin.BoxLayout{} end
	local ratings = performance.ratings(info.modelIds, info.modifiers)
	if not ratings then return builtin.BoxLayout{} end
	return builtin.BoxLayout{ children = {
		content_card.ContentCard{
			meta = { localKey = "uioVehiclePerformance" },
			title = _("Performance"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(Card,
				{ ratings = ratings, entityId = params.entityId }),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		},
	} }
end

-- Cart tooltip --------------------------------------------------------------------------------------

-- The rating the cart computed last and has not shown yet: { text, tooltip }.
local pending

local function wrap_rating(original)
	return function(...)
		local result = original(...)
		if result and react.getCurrentRecipeName() == "VehicleCart" then pending = result end
		return result
	end
end

local function wrap_text_view(original)
	return function(...)
		if pending and react.getCurrentRecipeName() ~= "VehicleCart" then pending = nil end
		if pending then
			local p = select("#", ...) == 1 and select(1, ...) or nil
			if type(p) == "table" and p.text == pending[1] then
				local tooltip = pending[2]
				pending = nil
				local meta = {}
				for k, v in pairs(p.meta or {}) do meta[k] = v end
				if meta.tooltip == nil then meta.tooltip = tooltip end
				local copy = {}
				for k, v in pairs(p) do copy[k] = v end
				copy.meta = meta
				return original(copy)
			end
		end
		return original(...)
	end
end

--- Called from the react-replacement-config before the UI starts.
function performance.install(_replacement_api)
	if type(vehicle_util.getPowerRatingTextAndToolTip) ~= "function" then error("rating function not found") end
	vehicle_util.getPowerRatingTextAndToolTip = wrap_rating(vehicle_util.getPowerRatingTextAndToolTip)
	builtin.TextView = wrap_text_view(builtin.TextView)
	debugPrint("[ui_overhaul] performance tooltip installed")
end

return performance
