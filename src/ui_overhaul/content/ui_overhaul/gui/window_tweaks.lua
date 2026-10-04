--- Small fixes inside existing windows:
--   * sections of entity windows (Suppliers, Stocks, Passengers ...) stay open when the window is
--     opened again, and opening one no longer closes the others
--   * "Sell" in the vehicle window asks first: the first click turns the button into "Sell?", the
--     second sells (the Line Manager already asks before selling)
--   * the town window's level card names what limits growth ("Limited by Traffic") and shows the
--     progress towards the next town level as text (base: colours and a tooltip only)
--   * a perk locked by rank says "Promotion pending - open the Company window" when the rank is
--     already reached but not yet applied (the game applies a promotion only when the Company window
--     is opened, while the game bar already shows the new rank)
-- Wraps the module functions content_card.makeContentCardsCollapsibleFunctions, content_card.makeRecipeAndParam and
-- company_util.getConstructionDisableReason (GUI state only), each calling the previous one, and replaces the recipe
-- entity_window_util.ActionButtonBar; installed before the UI starts (window_tweaks.script.lua).
-- @module ui_overhaul.gui.window_tweaks
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

---@class uo.gui.window_tweaks
local window_tweaks = {}

-- Sections ----------------------------------------------------------------------------------------

---@alias uo.sections.Expanded table<string, boolean> section key -> expanded
---@alias uo.sections.State react.State<uo.sections.Expanded>
---@alias uo.sections.Update fun(key: string, expanded: boolean)
---@alias uo.sections.IsExpanded fun(key: string): boolean
---@alias uo.sections.Make fun(state: uo.sections.State, only_one: boolean): uo.sections.Update, uo.sections.IsExpanded

local remembered = {} ---@type uo.sections.Expanded for the session

-- The base "collapse all" key: vehicle.tl:501 closes every section with it before Modify, so that the
-- vehicle config change reaches the engine before a section shows it again. The base never reopens
-- them (the store stays open for further changes), so a window state that holds this key stays
-- collapsed: its sections no longer fall back to `remembered`. `remembered` itself is kept, as the
-- collapse is not the player's choice; the next window opens their sections again.
local COLLAPSE_ALL = ""

--- Wraps the previous makeContentCardsCollapsibleFunctions (base or another mod's wrap). Every base
-- window passes onlyOneExpandable = true; section keys deliberately go through the previous function
-- with false, because several sections may be open at once (README: "stay open the next time, and
-- several can be open at once"). COLLAPSE_ALL keeps the caller's value, so the base collapse runs.
---@param previous uo.sections.Make
---@return uo.sections.Make
function window_tweaks.wrap_collapsible(previous)
	return function(state, only_one_expandable)
		local update_section, is_expanded_base = previous(state, false)
		local update_all = previous(state, only_one_expandable)
		---@param key string
		---@param expanded boolean
		local function update(key, expanded)
			if key == COLLAPSE_ALL then
				update_all(key, expanded)
			else
				remembered[key] = expanded
				update_section(key, expanded)
			end
		end
		---@param key string
		---@return boolean
		local function is_expanded(key)
			local own = state:old()
			if own[key] == nil and own[COLLAPSE_ALL] == nil and remembered[key] ~= nil then
				return remembered[key]
			end
			return is_expanded_base(key)
		end
		return update, is_expanded
	end
end

local function patch_sections()
	content_card.makeContentCardsCollapsibleFunctions =
		window_tweaks.wrap_collapsible(content_card.makeContentCardsCollapsibleFunctions)
end

-- Sell confirmation -------------------------------------------------------------------------------

local SELL_TAG = "entityWindow.vehicle.sell"
local ARMED_SECONDS = 4

---@param icon? string
---@param text? string
---@return react.TreeNodeId
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
---@class uo.window_tweaks.ConfirmSellParams: react.Param
---@field entry game.gui.entity_window.entity_window_util.ActionBarButton

---@param params uo.window_tweaks.ConfirmSellParams
---@return react.TreeNodeId
local ConfirmSellButton = react.RegisterRecipe("UioConfirmSellButton", function(params)
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

--- A copy of `t` with the same fields and values.
---@generic T: table
---@param t T
---@return T
local function shallow_copy(t)
	local copy = {}
	-- LuaLS cannot infer pairs()'s key and value types for a generic table
	---@diagnostic disable-next-line: no-unknown
	for k, v in pairs(t) do copy[k] = v end
	return copy
end

---@param buttons? game.gui.entity_window.entity_window_util.ActionBarButton[]
---@return game.gui.entity_window.entity_window_util.ActionBarButton[]?
local function with_confirmation(buttons)
	if not buttons then return buttons end
	local result = {} ---@type game.gui.entity_window.entity_window_util.ActionBarButton[]
	for i, entry in ipairs(buttons) do
		if entry.tag == SELL_TAG and not entry.customItem and not entry.toggleButton and entry.sound then
			-- `sound` is only set when selling is allowed; otherwise the base click shows the reason
			local copy = shallow_copy(entry)
			copy.customItem = ConfirmSellButton{ entry = entry }
			result[i] = copy
		else
			result[i] = entry
		end
	end
	return result
end

---@param params game.gui.entity_window.entity_window_util.ActionButtonBarParams
---@return react.TreeNodeId
local ActionButtonBar = react.RegisterRecipe("ActionButtonBar", function(params)
	local ok, changed = pcall(function()
		local copy = shallow_copy(params)
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

---A growth factor: a town rating, or the supplies.
---@class uo.window_tweaks.GrowthFactor
---@field name string
---@field fn ResName parallel function computing the factor's RatingLevel
---@field extra? any the rating's getRatingFnExtraParam, whatever that rating needs

-- Growth = (lowest of these ratings) x supplies (town_util.calcAuthorityScore, getGrowthLevelMult).
---@return uo.window_tweaks.GrowthFactor[]
local function growth_factors()
	local factors = {} ---@type uo.window_tweaks.GrowthFactor[]
	for _i, rating in ipairs(town_util.GetRatings()) do
		factors[#factors + 1] = { name = rating.name, fn = rating.getRatingFnName, extra = rating.getRatingFnExtraParam }
	end
	factors[#factors + 1] = { name = _("Supplies"), fn = PARALLEL .. "getRatingDeliveries" }
	return factors
end

--- True once the bottleneck text failed; from then on the base card is shown alone.
window_tweaks.town_level_failed = false

---@param err any what pcall caught: an error can be any Lua value
local function town_level_failed(err)
	if window_tweaks.town_level_failed then return end
	window_tweaks.town_level_failed = true
	debugPrint("[ui_overhaul] town level text failed, showing the base card: ", tostring(err))
end

---@class uo.town.States
---@field factors react.State<RatingLevel|nil>[] growth level of each factor, in the order of the factor list
---@field level_widget react.State<game.game_mechanics.towns.town_util_parallel.TownLevelWidgetState|nil>
---@field development react.State<boolean|nil>

--- The hooks of the bottleneck text, one parallel state per factor, then the level and development
-- states.
---@param town Engine.Entity
---@param factors uo.window_tweaks.GrowthFactor[] growth_factors()
---@return uo.town.States
local function use_town_states(town, factors)
	local factor_states = {} ---@type react.State<RatingLevel|nil>[]
	for i, factor in ipairs(factors) do
		---@type game.game_mechanics.towns.town_util_parallel.GetRatingParam
		local param = { townEntity = town, extraParam = factor.extra }
		factor_states[i] = engine_react_util.useStepStateParallelSimple(factor.fn, param)
	end
	local level_widget = engine_react_util.useStepStateParallelSimple(PARALLEL .. "getTownLevelWidgetState", town)
	local development = engine_react_util.useStepState(function()
		local component = api.engine.getComponent(town, api.type.ComponentType.TOWN)
		return component and component.developmentActive
	end)
	return { factors = factor_states, level_widget = level_widget, development = development }
end

--- The text under the base level widget, or nil.
---@param factors uo.window_tweaks.GrowthFactor[] growth_factors()
---@param states uo.town.States
---@return react.TreeNodeId|nil
local function bottleneck_text(factors, states)
	if not states.development:old() then return nil end
	local worst, worst_rank = nil, math.huge
	for i, factor in ipairs(factors) do
		local rank = LEVEL_RANK[states.factors[i]:old()] or math.huge
		if rank < worst_rank then worst, worst_rank = factor, rank end
	end
	local parts = {} ---@type string[]
	if worst and worst_rank < LEVEL_RANK.Excellent then
		parts[#parts + 1] = lang_util.format(_("Limited by {factor}"), { factor = worst.name })
	end
	-- nil until the parallel function has run once, or if the game no longer has it
	-- (useStepStateParallel logs that instead of raising)
	local level_state = states.level_widget:old()
	if level_state and level_state.experience then
		local level, fraction = town_cargo_util.getLevelAndFraction(level_state.experience)
		parts[#parts + 1] = lang_util.format(_("{percentage} Towards {nextTownLevelName}"), {
			percentage = api.util.toStringPercent(fraction), nextTownLevelName = town_util.level2name(level + 1) })
	end
	if #parts == 0 then return nil end
	return builtin.TextView{ meta = { class = "font-scale-body", id = "uio.town.bottleneck" },
		text = table.concat(parts, "  \xC2\xB7  ") }
end

-- Owns every hook of the town level text, so that its parent declares none. One instance always
-- declares the same hooks in the same order: the factor list is fixed on its first render, and a
-- failure does not skip hooks on later renders. After a failure it renders an empty layout until
-- the parent, which checks town_level_failed, unmounts it.
---@class uo.window_tweaks.TownBottleneckParams: react.Param
---@field town Engine.Entity

---@param params uo.window_tweaks.TownBottleneckParams
---@return react.TreeNodeId
local TownBottleneck = react.RegisterRecipe("UioTownBottleneck", function(params)
	local factors_ref = react.useRef(nil)
	if factors_ref:get() == nil then
		local ok, factors = pcall(growth_factors)
		if not ok then town_level_failed(factors) end
		factors_ref:set(ok and factors or false)
	end
	local factors = factors_ref:get() or {}
	local ok, states = pcall(use_town_states, params.town, factors)
	if not ok then town_level_failed(states) end
	local node ---@type react.TreeNodeId?
	if not window_tweaks.town_level_failed then
		local text_ok, text = pcall(bottleneck_text, factors, states)
		if text_ok then node = text else town_level_failed(text) end
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical,
		children = { not window_tweaks.town_level_failed and node or nil } }
end)

-- Declares no hooks: the base widget, and the text below it while it works. The text is a child
-- recipe, so dropping it after a failure unmounts it instead of changing this recipe's hooks.
---The param the base passes to the town level card's content recipe.
---@class uo.window_tweaks.TownLevelParam
---@field entityId Engine.Entity

---@class uo.window_tweaks.TownLevelWithBottleneckParams: react.Param
---@field inner react.Recipe<uo.window_tweaks.TownLevelParam> the base content recipe
---@field innerParam uo.window_tweaks.TownLevelParam

---@param params uo.window_tweaks.TownLevelWithBottleneckParams
---@return react.TreeNodeId
local TownLevelWithBottleneck = react.RegisterRecipe("UioTownLevel", function(params)
	local children = { params.inner(params.innerParam) } ---@type react.TreeNodeId[]
	if not window_tweaks.town_level_failed then
		local ok, node = pcall(TownBottleneck, { meta = { localKey = "uio.town.bottleneck" },
			town = params.innerParam.entityId })
		if ok then children[2] = node else town_level_failed(node) end
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end)

-- The town level card's content is a local recipe; it is created through makeRecipeAndParam while
-- TownLevelPlugin renders, with the parameter { entityId } (the other card part uses { entity }).
local function patch_town_level()
	local original = content_card.makeRecipeAndParam
	---@generic T
	---@param recipe react.Recipe<T>
	---@param param T
	---@return game.gui.main.content_card.RecipeAndParamErased
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
	---@param res ResName
	---@param metadata ConstructionDescMetadata
	---@param cache game.game_mechanics.company.company_util.ConstructionDisableCacheData
	---@return game.game_mechanics.company.company_util.ItemDisableReason?
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
---@param replacement_api react.ReplacementApi
function window_tweaks.install(replacement_api)
	patch_sections()
	patch_disable_reason()
	patch_town_level()
	replacement_api.ReplaceRecipe(entity_window_util.ActionButtonBar, ActionButtonBar)
end

return window_tweaks
