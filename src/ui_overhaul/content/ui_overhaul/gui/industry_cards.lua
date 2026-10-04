--- Two cards in the vanilla industry window, from the game's own widgets and styles:
--   * Development: the level ("Level 2 of 4"), the recipes in words ("2 Coal + 1 Iron ore -> 1 Steel,
--     up to 400 per year"), how likely the industry is to expand at its next half-yearly check,
--     with the production rating and the share of its output that is shipped, and what keeps it
--     from expanding (maximum level, something in the way, nothing produced or shipped, closure
--     countdown, developed by hand, owned by the player). The game's own rule is in
--     core/industry_development.lua.
--   * Served by: the player's lines with a stop whose catchment area reaches the industry, each a
--     clickable name.
-- A plugin of ::IndustryEowExtensionPoint (industry_card.res.lua), rendered through the guarded
-- stub industry_cards.script.lua. State functions only read the engine; rendering translates.
-- @module ui_overhaul.gui.industry_cards
local builtin = require("::/gui/main/builtin.lua")
local content_card = require("::/gui/main/content_card.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local react = require("::/gui/main/react.lua")
-- loaded at render time (guard.plugin): only fully qualified paths reach this mod
local development = require("ui_overhaul_1::/ui_overhaul/core/industry_development.lua")

local industry_cards = {}

local REFRESH = 2.0 -- seconds
local SERVED_REFRESH = 5.0 -- the line search walks all the player's stops
local MAX_LINES = 8

local function vertical(children, class)
	return builtin.BoxLayout{ meta = { class = class }, orientation = builtin.type.Orientation.Vertical,
		children = children }
end

local function text(value, class, tooltip)
	return builtin.TextView{ meta = { class = class or "font-scale-body", tooltip = tooltip }, text = value }
end

local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

-- Data -----------------------------------------------------------------------------------------------

-- Whether the industries script found something in the way of this industry's next level.
local function failed_expansion(entity)
	local script = api.engine.system.gameScriptSystem.getEntityForGameScript("::/game_mechanics/industries/industries.gs")
	local game_script = script and api.engine.getComponent(script, api.type.ComponentType.GAME_SCRIPT)
	local failed = game_script and game_script.state_native:find("industryFailedExtensions")
	return failed ~= nil and failed:find(entity) ~= nil
end

-- Recipes as { inputs = { {cargo, amount} }, outputs = { {cargo, amount, perYear} } }.
local function read_recipes(stock_list_entity)
	local stock_list = api.engine.getComponent(stock_list_entity, api.type.ComponentType.STOCK_LIST)
	local result = {}
	for _i, rule in ipairs(stock_list and stock_list.rules or {}) do
		if not rule.booster then
			-- the first alternative, as the game's own widgets show it
			local inputs = {}
			for stock_index, amount in ipairs(rule.input[1] or {}) do
				local stock = stock_list.stocks[stock_index]
				if amount > 0 and stock then inputs[#inputs + 1] = { stock.cargoType, amount } end
			end
			local outputs = {}
			for key, amount in pairs(rule.output) do
				if amount > 0 then
					local cargo = key
					-- keyed by stock index, as the inputs are (a key without a stock is a cargo type id)
					local stock = stock_list.stocks[key]
					if stock then cargo = stock.cargoType end
					outputs[#outputs + 1] = { cargo, amount,
						api.engine.util.stock.getCargoMaxProductionPerYear(stock_list_entity, cargo) }
				end
			end
			table.sort(outputs, function(a, b) return a[1] < b[1] end)
			if #inputs > 0 or #outputs > 0 then result[#result + 1] = { inputs = inputs, outputs = outputs } end
		end
	end
	return result
end

--- Plain facts about industry `entity`. Engine reads only.
function industry_cards.read(entity)
	local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
	if not industry then return nil end
	local stock = industry.stockList
	local output = api.engine.util.stock.getCargoOutputPerYear(stock)
	local shipped = api.engine.util.stock.getCargoShippedPerYear(stock)
	local rating = api.engine.util.stock.getProductionRating(stock)
	local chance, effective = development.chance(rating, shipped, output)
	local facts = {
		level = industry.level,
		maxLevel = industry.maxLevel,
		manual = industry.manualDevelopment,
		playerOwned = api.engine.getComponent(entity, api.type.ComponentType.PLAYER_OWNED) ~= nil,
		output = output,
		shipped = shipped,
		productionRating = rating,
		rating = effective,
		chance = chance,
		closing = industry.closureTimeStamp > 0,
		closesIn = industry.closureTimeStamp > 0 and math.max(0, industry.closureTimeStamp - now()) or nil,
		blocked = failed_expansion(entity),
		recipes = read_recipes(stock),
	}
	facts.blockers = development.blockers(facts)
	return facts
end

--- The player's lines with a stop whose catchment reaches the industry: { {line, stopIndex} }.
function industry_cards.read_lines(entity)
	local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
	if not industry then return {} end
	local targets = { [entity] = true, [industry.stockList] = true }
	local reaches = {} -- station -> boolean, per pass
	local function station_reaches(station)
		if reaches[station] == nil then
			reaches[station] = false
			for _i, catchable in ipairs(api.engine.system.catchmentAreaSystem.getStationCatchables(station, true)) do
				if targets[catchable] then reaches[station] = true break end
			end
		end
		return reaches[station]
	end
	local result = {}
	for _i, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
		for stop_index, stop in ipairs(component and component.stops or {}) do
			local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
			local station = group and group.stations[stop.station + 1]
			if station and station_reaches(station) then
				result[#result + 1] = { line, stop_index }
				break
			end
		end
	end
	return result
end

-- Texts ------------------------------------------------------------------------------------------------

local function cargo_name(id) return _(api.res.cargoTypeRep.get(id).name) end

local function amounts(list)
	local parts = {}
	for _i, entry in ipairs(list) do parts[#parts + 1] = string.format("%d %s", entry[2], cargo_name(entry[1])) end
	return table.concat(parts, " + ")
end

local function recipe_text(recipe)
	local per_year = 0
	for _i, output in ipairs(recipe.outputs) do per_year = per_year + (output[3] or 0) end
	local rule = (#recipe.inputs > 0 and (amounts(recipe.inputs) .. " \xE2\x86\x92 ") or "") .. amounts(recipe.outputs)
	if per_year > 0 then
		return lang_util.format(_("{recipe}, up to {amount} per year"),
			{ recipe = rule, amount = lang_util.formatInt(per_year) })
	end
	return rule
end

local function blocker_text(key, f)
	if key == "max_level" then return _("Industry is expanded to it's full potential.") end
	if key == "blocked" then return _("Industry is blocked from further expansion.") end
	if key == "manual" then return _("It only changes when developed by hand.") end
	if key == "player_owned" then return _("You own it: it does not expand by itself.") end
	if key == "no_output" then return _("It produces nothing yet: deliver its inputs.") end
	if key == "not_shipped" then return _("Too little of its output is transported to expand.") end
	if key == "closing" then
		local util = require("::/scripts/util.tl")
		local speed = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED)
		return lang_util.format(_("It closes in {duration} unless its cargo is used."),
			{ duration = util.formatDurationWithCurrentCalenderSpeed(f.closesIn or 0, speed.millisPerDay) })
	end
	return nil
end

local function percent(v) return api.util.toStringPercentPrecision(v or 0, 0) end

-- Cards -------------------------------------------------------------------------------------------------

local Development = react.RegisterRecipe("UioIndustryDevelopment", function(params)
	local state = engine_react_util.useStepStateTimer(function()
		local ok, facts = pcall(industry_cards.read, params.entity)
		return ok and facts or nil
	end, REFRESH)
	local f = state:old()
	if not f then return vertical{} end
	-- the level only while the industry can still grow (the game marks the maximum with a text)
	local children = {}
	if f.level < f.maxLevel then
		children[1] = text(lang_util.format(_("Level {level} of {max}"),
			{ level = lang_util.formatInt(f.level), max = lang_util.formatInt(f.maxLevel) }), "font-scale-headline")
	end
	for _i, recipe in ipairs(f.recipes) do children[#children + 1] = text(recipe_text(recipe)) end
	if f.level < f.maxLevel then
		children[#children + 1] = text(lang_util.format(_("Chance to expand at the next check: {chance}"),
			{ chance = percent(#f.blockers == 0 and f.chance or 0) }), "font-scale-body, uio-industry-chance",
			_("Every half year the industry may expand, if it produces well and its output is transported."))
		local template = _("Production rating {rating}, {shipped} of {output} per year transported")
		children[#children + 1] = text(lang_util.format(template, {
			rating = percent(f.productionRating),
			shipped = lang_util.formatInt(f.shipped),
			output = lang_util.formatInt(f.output),
		}), "font-scale-annotation")
	end
	for _i, key in ipairs(f.blockers) do
		local line = blocker_text(key, f)
		if line then
			local class = key == "max_level" and "font-scale-body" or "font-scale-body, uio-industry-blocker"
			children[#children + 1] = text(line, class)
		end
	end
	return builtin.BoxLayout{ children = {
		builtin.Component{
			meta = { id = "uio.industry.development." .. tostring(params.entity) },
			layout = vertical(children, "uio-industry-development"),
		},
	} }
end)

local ServedBy = react.RegisterRecipe("UioIndustryServedBy", function(params)
	local state = engine_react_util.useStepStateTimer(function()
		local ok, lines = pcall(industry_cards.read_lines, params.entity)
		return ok and lines or {}
	end, SERVED_REFRESH)
	local lines = state:old() or {}
	if #lines == 0 then
		return vertical{ text(_("No line of yours stops within reach of this industry."), "font-scale-body") }
	end
	local children = {}
	for i, entry in ipairs(lines) do
		if i > MAX_LINES then
			children[#children + 1] = text(lang_util.format(_("and {count} more"),
				{ count = lang_util.formatInt(#lines - MAX_LINES) }), "font-scale-annotation")
			break
		end
		children[#children + 1] = builtin.BoxLayout{
			meta = { localKey = tostring(entry[1]) },
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				line_react_util.ColorWidget{ entity = entry[1] },
				line_react_util.NameTextView{ entity = entry[1], locationButton = false, stackEntityOpen = true,
					editMode = false },
			},
		}
	end
	return vertical(children, "uio-industry-lines")
end)

local function card(local_key, title, recipe, param, params)
	return content_card.ContentCard{
		meta = { localKey = local_key },
		title = title,
		initialCalloutTextPermanent = "",
		recipeAndParamPermanent = content_card.makeRecipeAndParam(recipe, param),
		gameCtx = params.gameCtx,
		showOnRightSide = params.showCalloutOnRightSide,
	}
end

--- Plugin recipe body of the industry window.
function industry_cards.industry(params)
	local entity = params.entityId
	if not entity or not api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY) then
		return builtin.BoxLayout{}
	end
	return vertical({
		card("uioIndustryDevelopment", _("Development"), Development, { entity = entity }, params),
		card("uioIndustryServedBy", _("Served by"), ServedBy, { entity = entity }, params),
	}, "box-plugin-vertical-space")
end

return industry_cards
