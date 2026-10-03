--- Small fixes inside existing windows, nothing new to learn:
--   * sections of entity windows (Suppliers, Stocks, Passengers ...) stay open when the window is
--     opened again, and opening one no longer closes the others
--   * "Sell" in the vehicle window asks first: the first click turns the button into "Sell?", the
--     second sells (the Line Manager already asks before selling)
--   * the town window's level card names what limits growth ("Limited by Traffic") and shows the
--     progress towards the next town level as text (base: colours and a tooltip only)
--   * a perk locked by rank says "Promotion pending - open the Company window" when the rank is
--     already reached but not yet applied (the game applies a promotion only when the Company window
--     is opened, while the game bar already shows the new rank)
-- Patches the module functions content_card.makeContentCardsCollapsibleFunctions and
-- company_util.getConstructionDisableReason (GUI state only) and wraps the exported recipe
-- entity_window_util.ActionButtonBar; installed before the UI starts (window_tweaks.script.lua).
-- @module ux_overhaul.gui.window_tweaks
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local content_card = require("::/gui/main/content_card.tl")
local entity_window_util = require("::/gui/entity_window/entity_window_util.tl")
local company_util = require("::/game_mechanics/company/company_util.tl")
local company_metadata = require("::/game_mechanics/company/company_metadata.tl")
local company_static_util = require("::/game_mechanics/company/company_static_util.tl")
local company_progression_util = require("::/game_mechanics/company/company_progression_util.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local town_util = require("::/game_mechanics/towns/town_util.tl")
local town_cargo_util = require("::/game_mechanics/towns/town_cargo_util.tl")

local window_tweaks = {}

-- Sections ----------------------------------------------------------------------------------------

local remembered = {} -- section key -> expanded, for the session

local function patch_sections()
	content_card.makeContentCardsCollapsibleFunctions = function(state, _only_one_expandable)
		local function update(key, expanded)
			local new_state = {}
			for k, v in pairs(state:old()) do new_state[k] = v end
			if key == "" then
				-- base "collapse all" (vehicle window before Modify); not remembered
				for k in pairs(new_state) do new_state[k] = false end
			else
				remembered[key] = expanded
			end
			new_state[key] = expanded
			state:set(new_state)
		end
		local function is_expanded(key)
			local value = state:old()[key]
			if value == nil then return remembered[key] == true end
			return value == true
		end
		return update, is_expanded
	end
end

-- Sell confirmation -------------------------------------------------------------------------------

local SELL_TAG = "entityWindow.vehicle.sell"
local ARMED_SECONDS = 4

local function button_content(icon, text)
	return builtin.Component{
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				icon and builtin.ImageView{ path = icon, scaling = builtin.type.ImageViewScaling.AutoFit } or nil,
				text and builtin.TextView{ meta = { class = "font-scale-body" }, text = text } or nil,
			},
		},
	}
end

-- The vanilla secondary (icon) button; armed, it shows "Sell?" like a primary button and the sell
-- sound plays on the confirming click.
local ConfirmSellButton = react.RegisterRecipe("UxoConfirmSellButton", function(params)
	local entry = params.entry
	local armed = react.useState(false)
	local ticks = react.useRef(0)
	react.onStepTimer(function()
		if not armed:old() then return end
		ticks:set(ticks:get() + 1)
		if ticks:get() >= ARMED_SECONDS then armed:set(false) end
	end, 1.0)
	if armed:old() then
		return builtin.BoxLayout{ children = { builtin.Button{
			meta = { class = "primary, sell-sfx", tag = entry.tag },
			onClick = function()
				armed:set(false)
				entry.onClick()
			end,
			content = button_content(entry.icon, entry.description .. "?"),
		} } }
	end
	return builtin.BoxLayout{ children = { builtin.Button{
		meta = { class = "secondary", tooltip = entry.description, tag = entry.tag },
		onClick = function()
			ticks:set(0)
			armed:set(true)
		end,
		content = button_content(entry.icon, nil),
	} } }
end)

local function with_confirmation(buttons)
	if not buttons then return buttons end
	local result = {}
	for i, entry in ipairs(buttons) do
		if entry.tag == SELL_TAG and not entry.customItem and not entry.toggleButton and entry.sound then
			-- `sound` is only set when selling is allowed; otherwise the base click shows the reason
			local copy = {}
			for k, v in pairs(entry) do copy[k] = v end
			copy.customItem = ConfirmSellButton{ entry = entry }
			result[i] = copy
		else
			result[i] = entry
		end
	end
	return result
end

local ActionButtonBar = react.RegisterRecipe("ActionButtonBar", function(params)
	local ok, changed = pcall(function()
		local copy = {}
		for k, v in pairs(params) do copy[k] = v end
		copy.primaryButtons = with_confirmation(params.primaryButtons)
		copy.secondaryButtons = with_confirmation(params.secondaryButtons)
		return copy
	end)
	local bar = react.CallOriginalRecipe(entity_window_util.ActionButtonBar, ok and changed or params)
	return builtin.BoxLayout{ children = { bar } }
end)

-- Town growth bottleneck ------------------------------------------------------------------------

local PARALLEL = "::/game_mechanics/towns/town_util_parallel.script@town_util_parallel."
local LEVEL_RANK = { VeryPoor = 0, Poor = 1, Mediocre = 2, Good = 3, VeryGood = 4, Excellent = 5 }

-- Growth = (lowest of these ratings) x supplies (town_util.calcAuthorityScore, getGrowthLevelMult).
local function growth_factors()
	local factors = {}
	for _i, rating in ipairs(town_util.GetRatings()) do
		factors[#factors + 1] = { name = rating.name, fn = rating.getRatingFnName, extra = rating.getRatingFnExtraParam }
	end
	factors[#factors + 1] = { name = _("Supplies"), fn = PARALLEL .. "getRatingDeliveries" }
	return factors
end

local TownLevelWithBottleneck = react.RegisterRecipe("UxoTownLevel", function(params)
	local town = params.innerParam.entityId
	-- hooks in a fixed order: one parallel state per factor, plus the level state
	local worst, worst_rank = nil, math.huge
	for _i, factor in ipairs(growth_factors()) do
		local level = engine_react_util.useStepStateParallelSimple(factor.fn,
			{ townEntity = town, extraParam = factor.extra })
		local rank = LEVEL_RANK[level:old()] or math.huge
		if rank < worst_rank then worst, worst_rank = factor, rank end
	end
	local levelState = engine_react_util.useStepStateParallelSimple(PARALLEL .. "getTownLevelWidgetState", town)
	local development = engine_react_util.useStepState(function()
		local component = api.engine.getComponent(town, api.type.ComponentType.TOWN)
		return component and component.developmentActive
	end)
	local children = { params.inner(params.innerParam) }
	if development:old() then
		local level, fraction = town_cargo_util.getLevelAndFraction(levelState:old().experience)
		local parts = {}
		if worst and worst_rank < LEVEL_RANK.Excellent then
			parts[#parts + 1] = lang_util.format(_("Limited by {factor}"), { factor = worst.name })
		end
		parts[#parts + 1] = lang_util.format(_("{percentage} Towards {nextTownLevelName}"), {
			percentage = api.util.toStringPercent(fraction), nextTownLevelName = town_util.level2name(level + 1) })
		children[#children + 1] = builtin.TextView{ meta = { class = "font-scale-body", id = "uxo.town.bottleneck" },
			text = table.concat(parts, "  \xC2\xB7  ") }
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end)

-- The town level card's content is a local recipe; it is created through makeRecipeAndParam while
-- TownLevelPlugin renders, with the parameter { entityId } (the other card part uses { entity }).
local function patch_town_level()
	local original = content_card.makeRecipeAndParam
	content_card.makeRecipeAndParam = function(recipe, param)
		local ok, is_level = pcall(function()
			return type(param) == "table" and param.entityId ~= nil and param.entity == nil
				and react.getCurrentRecipeName() == "TownLevelPlugin"
		end)
		if ok and is_level then
			return original(TownLevelWithBottleneck, { inner = recipe, innerParam = param })
		end
		return original(recipe, param)
	end
end

-- Promotion pending -------------------------------------------------------------------------------

local function patch_disable_reason()
	local original = company_util.getConstructionDisableReason
	company_util.getConstructionDisableReason = function(res, metadata, cache)
		local result = original(res, metadata, cache)
		if not result or result.category ~= "company-rank" then return result end
		local ok, pending = pcall(function()
			local company = company_metadata.constructionDesc.get(metadata)
			local min_rank = company and company_static_util.getMinRankConsideringPermits(company)
			local state = company_progression_util.getCompanyProgressionState(api.engine.util.getPlayer())
			return min_rank and state and state.potentialLevel and min_rank <= state.potentialLevel
				and min_rank > cache.companyRank
		end)
		if ok and pending then
			return { reason = _("Promotion pending - open the Company window to unlock"), category = result.category }
		end
		return result
	end
end

--- Called from the react-replacement-config before the UI starts.
function window_tweaks.install(replacement_api)
	patch_sections()
	patch_disable_reason()
	patch_town_level()
	replacement_api.ReplaceRecipe(entity_window_util.ActionButtonBar, ActionButtonBar)
end

return window_tweaks
