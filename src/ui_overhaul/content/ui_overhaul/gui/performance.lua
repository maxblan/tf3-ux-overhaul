--- How a vehicle copes with slopes, where players decide about it:
--   * the vehicle window gets a Performance card: the game's rating (Poor to Excellent) and a table
--     of the top speed on flat track and on medium and steep slopes, with the time and distance it
--     takes to reach it; a switch shows it fully loaded or without load
--   * in the vehicle store's composition (the cart), the Performance row's tooltip shows the slope
--     speeds (the game computes them there and throws them away)
-- The figures follow the game's own formula (core/vehicle_slopes.lua, with the game's Romberg
-- integration), so they match the rating the store shows. The card is a plugin of
-- ::VehicleEowExtensionPoint (performance_card.res); the cart tooltip wraps
-- vehicle_util.getPowerRatingTextAndToolTip and builtin.TextView while the cart renders
-- (performance.res, react-replacement-config).
-- @module ui_overhaul.gui.performance
local builtin = require("::/gui/main/builtin.lua")
local content_card = require("::/gui/main/content_card.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local react = require("::/gui/main/react.lua")
local vehicle_store_util = require("::/gui/line_vehicle_mgmt/vehicle_store_util.tl")
local vehicle_util = require("::/gui/line_vehicle_mgmt/vehicle_util.tl")
local romberg = require("::/scripts/util/romberg.tl")
local vehicle_slopes = require("/ui_overhaul/core/vehicle_slopes.lua")
local builtin_wraps = require("ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua")

local performance = {}

local function text(value, class, tooltip)
	return builtin.TextView{ meta = { class = class or "font-scale-body", tooltip = tooltip }, text = value }
end

local function integrate(a, h, tolerance, fn)
	return romberg.rombergIntegration(a, h, tolerance, 9, fn)
end

local RATING_NAMES = { "Poor", "Mediocre", "Good", "Excellent" } -- vehicle_util.tl's words

-- Slope figures per consist: they depend only on the models and their maintenance modifiers.
local cache, cached = {}, 0
local CACHE_LIMIT = 64
local MODIFIER_FIELDS = { "topSpeedScale", "noiseScale", "pollutionScale", "comfortScale" }

local function cache_key(model_ids, modifiers)
	local parts = {}
	for i, id in ipairs(model_ids or {}) do parts[i] = tostring(id) end
	-- an engine object (TransportVehicle.Modifiers, userdata): read its fields by name
	local mods = {}
	for i, field in ipairs(MODIFIER_FIELDS) do
		local ok, value = pcall(function() return modifiers[field] end)
		mods[i] = tostring(ok and value or "")
	end
	return table.concat(parts, ",") .. "|" .. (modifiers and table.concat(mods, ",") or "")
end

local function compute(model_ids, modifiers)
	local vehicles = {}
	for i, model_id in ipairs(model_ids or {}) do
		vehicles[i] = vehicle_store_util.makeSingleVehicle(api.res.modelRep.get(model_id))
	end
	if #vehicles == 0 then return false end
	local data = vehicle_store_util.collectVehicleData(vehicles, modifiers)
	if not data or not (data.power > 0 and data.tractiveEffort > 0) then return false end
	local function rows(weight)
		return vehicle_slopes.compute({ weight = weight, power = data.power, tractiveEffort = data.tractiveEffort,
			speed = data.speed, rollingFriction = data.rollingFriction }, integrate)
	end
	-- the rating is the game's: the same formula, fully loaded (vehicle_util.getPowerRatingTextAndToolTip)
	local loaded, rating = rows(data.weight + data.weightMaxPayload)
	if not loaded then return false end
	return { rating = rating, loaded = loaded, empty = rows(data.weight) }
end

--- The rating word and the slope rows fully loaded and without load: { rating, loaded, empty }, or
-- nil for vehicles the game does not rate (no power or tractive effort: ships, aircraft, wagons).
-- Computed once per consist and kept; the rating word is translated here (GUI thread).
function performance.ratings(model_ids, modifiers)
	local key = cache_key(model_ids, modifiers)
	local entry = cache[key]
	if entry == nil then
		if cached >= CACHE_LIMIT then cache, cached = {}, 0 end
		entry = compute(model_ids, modifiers)
		cache[key], cached = entry, cached + 1
	end
	if not entry then return nil end
	return {
		rating = pGetText("vehicle-performance-rating", RATING_NAMES[entry.rating] or RATING_NAMES[1]),
		loaded = entry.loaded,
		empty = entry.empty,
	}
end

local SLOPE_NAMES = { "Flat", "Medium", "High" }

local function slope_rows(rows)
	local result = {
		builtin.Row{ cells = {
			text(_("Slope"), "font-scale-annotation, uio-performance-header"),
			text(_("Top Speed"), "font-scale-annotation, uio-performance-header"),
			text(_("Time"), "font-scale-annotation, uio-performance-header"),
			text(_("Distance"), "font-scale-annotation, uio-performance-header"),
		} },
	}
	for i, row in ipairs(rows) do
		local name = string.format("%s (%s)", pGetText("terrain-slope", SLOPE_NAMES[i]),
			api.util.toStringPercentPrecision(row.slope, 1))
		local cells = { text(name) }
		if row.enough then
			cells[2] = text(api.util.formatSpeed(row.speed))
			cells[3] = text(api.util.formatSeconds(math.floor(row.time + 0.5)))
			cells[4] = text(api.util.formatLength(row.distance))
		else
			cells[2] = text(_("Not enough power"), "font-scale-body, negative")
			cells[3] = text("")
			cells[4] = text("")
		end
		result[#result + 1] = builtin.Row{ cells = cells }
	end
	return result
end

local card_failed = false -- logged once

-- The card's content; `emptyState` is the recipe's state of the load switch.
local function render_card(params, emptyState)
	local r = params.ratings
	local show_empty = emptyState:old() and r.empty ~= nil
	local switch = r.empty and builtin.ToggleButtonGroup{
		meta = { class = "uio-performance-load" },
		buttons = {
			{ content = text(_("Fully loaded"), "font-scale-annotation") },
			{ content = text(_("Without load"), "font-scale-annotation") },
		},
		selected = show_empty and 2 or 1,
		onValueChange = function(index) emptyState:set(index == 2) end,
	} or nil
	return builtin.BoxLayout{
		meta = { class = "uio-performance", id = "uio.vehicle.performance." .. tostring(params.entityId) },
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.BoxLayout{
				orientation = builtin.type.Orientation.Horizontal,
				children = {
					text(_("Performance") .. ": " .. r.rating, "font-scale-headline"),
					gui_react_util.makeHorizontalSpacer(),
					switch,
				},
			},
			builtin.TableLayout{
				meta = { class = "uio-performance-table" },
				columnWeights = { 9, 11, 5, 6 },
				rows = slope_rows(show_empty and r.empty or r.loaded),
			},
		},
	}
end

local Card = react.RegisterRecipe("UioVehiclePerformance", function(params)
	local emptyState = react.useState(false)
	local ok, node = pcall(render_card, params, emptyState)
	if ok then return node end
	if not card_failed then
		card_failed = true
		debugPrint("[ui_overhaul] vehicle performance card failed: ", tostring(node))
	end
	return builtin.BoxLayout{}
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
		-- outside a render (a timer, another mod) there is no current recipe: nothing to do
		local ok, recipe = pcall(react.getCurrentRecipeName)
		if result and ok and recipe == "VehicleCart" then pending = result end
		return result
	end
end

local function wrap_text_view(original)
	return function(...)
		if pending then
			local ok, recipe = pcall(react.getCurrentRecipeName)
			if not ok or recipe ~= "VehicleCart" then pending = nil end
		end
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
	builtin_wraps.wrap("TextView", wrap_text_view)
	debugPrint("[ui_overhaul] performance tooltip installed")
end

return performance
