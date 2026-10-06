--- The vehicle window gets a Performance card with the rating the vehicle store shows for the same
-- consist (Poor to Excellent), computed by the game's own function
-- (vehicle_util.getPowerRatingTextAndToolTip, as vehicle_store_window.tl calls it), so the window
-- and the store always agree. The card is a plugin of ::VehicleEowExtensionPoint
-- (performance_card.res); vehicles the store does not rate (no power or tractive effort: ships,
-- aircraft, wagons) get no card.
-- @module ui_overhaul.gui.performance
local builtin = require("::/gui/main/builtin.lua")
local content_card = require("::/gui/main/content_card.tl")
local react = require("::/gui/main/react.lua")
local vehicle_store_util = require("::/gui/line_vehicle_mgmt/vehicle_store_util.tl")
local vehicle_util = require("::/gui/line_vehicle_mgmt/vehicle_util.tl")

---@class uo.gui.performance
local performance = {}

-- Ratings per consist: they depend only on the models and their maintenance modifiers. The word comes
-- translated from getPowerRatingTextAndToolTip, so it is computed while rendering (GUI thread).
local cache, cached = {}, 0 ---@type table<string, string|false>, integer
local CACHE_LIMIT = 64
---@type ("topSpeedScale"|"noiseScale"|"pollutionScale"|"comfortScale")[]
local MODIFIER_FIELDS = { "topSpeedScale", "noiseScale", "pollutionScale", "comfortScale" }

---@param model_ids? integer[]
---@param modifiers? Engine.Component.TransportVehicle.Modifiers
---@return string
local function cache_key(model_ids, modifiers)
	local parts = {} ---@type string[]
	for i, id in ipairs(model_ids or {}) do parts[i] = tostring(id) end
	-- an engine object (TransportVehicle.Modifiers, userdata): read its fields by name
	local mods = {} ---@type string[]
	for i, field in ipairs(MODIFIER_FIELDS) do
		---@return number?
		local function read() return modifiers and modifiers[field] end
		local ok, value = pcall(read)
		mods[i] = tostring(ok and value or "")
	end
	return table.concat(parts, ",") .. "|" .. (modifiers and table.concat(mods, ",") or "")
end

---@param model_ids? integer[]
---@param modifiers? Engine.Component.TransportVehicle.Modifiers
---@return string|false
local function compute(model_ids, modifiers)
	local vehicles = {} ---@type game.gui.line_vehicle_mgmt.vehicle_store_util.Vehicle[]
	for i, model_id in ipairs(model_ids or {}) do
		vehicles[i] = vehicle_store_util.makeSingleVehicle(api.res.modelRep.get(model_id))
	end
	if #vehicles == 0 then return false end
	local data = vehicle_store_util.collectVehicleData(vehicles, modifiers)
	if not data or not (data.power > 0 and data.tractiveEffort > 0) then return false end
	-- the store's call (vehicle_store_window.tl): fully loaded
	local rating = vehicle_util.getPowerRatingTextAndToolTip(data.weight + data.weightMaxPayload, data.power,
		data.tractiveEffort, data.speed, data.rollingFriction)
	return rating and rating[1] or false
end

--- The game's rating word for a consist (translated), or nil where the store shows none. Computed once
-- per consist and kept. GUI thread.
---@param model_ids? integer[]
---@param modifiers? Engine.Component.TransportVehicle.Modifiers
---@return string?
function performance.rating(model_ids, modifiers)
	local key = cache_key(model_ids, modifiers)
	local entry = cache[key]
	if entry == nil then
		if cached >= CACHE_LIMIT then cache, cached = {}, 0 end
		entry = compute(model_ids, modifiers)
		cache[key], cached = entry, cached + 1
	end
	return entry or nil
end

---@class uo.performance.CardParams: react.Param
---@field rating string
---@field entityId Engine.Entity

---@param params uo.performance.CardParams
---@return react.TreeNodeId
local Card = react.RegisterRecipe("UioVehiclePerformance", function(params)
	return builtin.BoxLayout{
		meta = { class = "uio-performance", id = "uio.vehicle.performance." .. tostring(params.entityId) },
		children = { builtin.TextView{ meta = { class = "font-scale-body" }, text = tostring(params.rating) } },
	}
end)

--- Plugin recipe body of the vehicle window (guarded by performance.script.lua).
---@param params game.gui.entity_window.vehicle.vehicle_eow.VehicleWidgetPluginParams
---@return react.TreeNodeId
function performance.card(params)
	if params.ownershipState ~= "Player" then return builtin.BoxLayout{} end
	local info = params.state and params.state.staticVehicleInfo
	if not info then return builtin.BoxLayout{} end
	local rating = performance.rating(info.modelIds, info.modifiers)
	if not rating then return builtin.BoxLayout{} end
	return builtin.BoxLayout{ children = {
		content_card.ContentCard{
			meta = { localKey = "uioVehiclePerformance" },
			title = _("Performance"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(Card, { rating = rating, entityId = params.entityId }),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		},
	} }
end

--- Called by installer.lua before the UI starts. The card is a plugin (performance_card.res.lua):
-- nothing to install, but the installer first checks the game still has what it uses (compat.lua).
---@param _replacement_api react.ReplacementApi
function performance.install(_replacement_api)
	debugPrint("[ui_overhaul] performance card installed")
end

return performance
