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
--
-- Blocked area: when something stands where the next level would go, the game paints that area red on
-- the map, in a colour the engine fixes (the plot overlay has no colour or transparency setting). The
-- blocker row has an eye button that shows or hides it, so the ground underneath can be seen. For
-- that the exported recipe IndustryWindow (industry.tl) is replaced and calls the original; while the
-- map action it hands to setActionFn renders, builtin.LayerConfig drops the overlay's triangles if
-- the area is switched off (industry_window.res.lua, industry_cards.script.lua).
-- @module ui_overhaul.gui.industry_cards
local builtin = require("::/gui/main/builtin.lua")
local content_card = require("::/gui/main/content_card.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local cargo_react_util = require("::/gui/main/cargo_react_util.tl")
local react = require("::/gui/main/react.lua")
local base_industry_window = require("::/gui/entity_window/industry/industry.tl")
-- loaded at render time (guard.plugin): only fully qualified paths reach this mod
local development = require("ui_overhaul_1::/ui_overhaul/core/industry_development.lua")
local builtin_wraps = require("ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")

---@class uo.gui.industry_cards
local industry_cards = {}

local REFRESH = 2.0 -- seconds
local SERVED_REFRESH = 5.0 -- the line search walks all the player's stops
local MAX_LINES = 8
local BLOCKED_AREA_EVENT = "uio.industry.blocked_area"

-- A card whose content fails shows nothing and logs once; its recipe declared its hooks before.
local report = guard.reporter("industry ", " card failed: ")

-- Whether the red area of a blocked expansion is shown on the map (for the session).
local show_blocked_area = true
-- True while the industry window's map action renders with the area switched off.
local strip_plots = false

---@param children react.TreeNodeId[]
---@param class? string
---@return react.TreeNodeId
local function vertical(children, class)
	return builtin.BoxLayout{ meta = { class = class }, orientation = builtin.type.Orientation.Vertical,
		children = children }
end

---@param value string
---@param class? string
---@param tooltip? string
---@return react.TreeNodeId
local function text(value, class, tooltip)
	return builtin.TextView{ meta = { class = class or "font-scale-body", tooltip = tooltip }, text = value }
end

---@return integer
local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

-- Data -----------------------------------------------------------------------------------------------

-- Whether the industries script found something in the way of this industry's next level.
---@param entity Engine.Entity
---@return boolean
local function failed_expansion(entity)
	local script = api.engine.system.gameScriptSystem.getEntityForGameScript("::/game_mechanics/industries/industries.gs")
	local game_script = script and api.engine.getComponent(script, api.type.ComponentType.GAME_SCRIPT)
	-- the script keeps a table there (industries.d.tl); the base reads it the same way (industry.tl:62)
	local failed = game_script and game_script.state_native:find("industryFailedExtensions") --[[@as NativeLuaTable?]]
	return failed ~= nil and failed:find(entity) ~= nil
end

---A recipe's cargo: { cargo type, amount } for inputs, { cargo type, amount, perYear } for outputs.
---@class uo.industry_cards.Amount
---@field [1] CargoTypeId
---@field [2] integer
---@field [3]? integer outputs: the most the industry can make per year

---@class uo.industry_cards.Recipe
---@field inputs uo.industry_cards.Amount[]
---@field outputs uo.industry_cards.Amount[]

-- Recipes as { inputs = { {cargo, amount} }, outputs = { {cargo, amount, perYear} } }.
---@param stock_list_entity Engine.Entity
---@return uo.industry_cards.Recipe[]
local function read_recipes(stock_list_entity)
	local stock_list = api.engine.getComponent(stock_list_entity, api.type.ComponentType.STOCK_LIST)
	local result = {} ---@type uo.industry_cards.Recipe[]
	if not stock_list then return result end
	for _i, rule in ipairs(stock_list.rules) do
		if not rule.booster then
			-- the first alternative, as the game's own widgets show it
			local inputs = {} ---@type uo.industry_cards.Amount[]
			for stock_index, amount in ipairs(rule.input[1] or {}) do
				local stock = stock_list.stocks[stock_index]
				if amount > 0 and stock then inputs[#inputs + 1] = { stock.cargoType, amount } end
			end
			local outputs = {} ---@type uo.industry_cards.Amount[]
			-- outputs are keyed by cargo type id (inputs by stock index), as industry_util.tl reads them
			for cargo, amount in pairs(rule.output) do
				if amount > 0 then
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

---@class uo.industry_cards.Facts: uo.core.industry_development.Facts
---@field output integer per year
---@field shipped integer per year
---@field productionRating number
---@field rating? number the effective rating, nil without output
---@field chance number
---@field closesIn? integer milliseconds of game time until the industry closes
---@field recipes uo.industry_cards.Recipe[]
---@field blockers uo.core.industry_development.Blocker[]

--- Plain facts about industry `entity`. Engine reads only.
---@param entity Engine.Entity
---@return uo.industry_cards.Facts?
function industry_cards.read(entity)
	local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
	if not industry then return nil end
	local stock = industry.stockList
	local output = api.engine.util.stock.getCargoOutputPerYear(stock)
	local shipped = api.engine.util.stock.getCargoShippedPerYear(stock)
	local rating = api.engine.util.stock.getProductionRating(stock)
	local chance, effective = development.chance(rating, shipped, output)
	---@type uo.industry_cards.Facts
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
		blockers = {}, -- from the complete facts, below
	}
	facts.blockers = development.blockers(facts)
	return facts
end


--- `facts` as the industry window's own expansion check sees them: the half-yearly check's record
-- of a failed expansion stays until the next check, but once the way is clear (the player removed
-- or terraformed what stood there) the window no longer finds a collision and drops the red area.
-- `colliding` is that check's result (IndustryEowState.failedExpansion); nil leaves `facts` as read.
---@param facts? uo.industry_cards.Facts
---@param colliding? boolean
---@return uo.industry_cards.Facts?
function industry_cards.live(facts, colliding)
	if not (facts and facts.blocked and colliding == false) then return facts end
	local copy = guard.shallow_copy(facts)
	copy.blocked = false
	copy.blockers = development.blockers(copy)
	return copy
end

---A line and the 1-based index of its stop that reaches the industry.
---@alias uo.industry_cards.ServingLine [Engine.Entity, integer]

--- The player's lines with a stop whose catchment reaches the industry: { {line, stopIndex} }.
---@param entity Engine.Entity
---@return uo.industry_cards.ServingLine[]
function industry_cards.read_lines(entity)
	local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
	if not industry then return {} end
	local targets = { [entity] = true, [industry.stockList] = true }
	local reaches = {} ---@type table<Engine.Entity, boolean> station -> boolean, per pass
	---@param station Engine.Entity
	---@return boolean
	local function station_reaches(station)
		if reaches[station] == nil then
			reaches[station] = false
			for _i, catchable in ipairs(api.engine.system.catchmentAreaSystem.getStationCatchables(station, true)) do
				if targets[catchable] then reaches[station] = true break end
			end
		end
		return reaches[station]
	end
	local result = {} ---@type uo.industry_cards.ServingLine[]
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


---@param key uo.core.industry_development.Blocker
---@param f uo.industry_cards.Facts
---@return string?
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
		---@cast speed -nil -- the world always has a game speed
		return lang_util.format(_("It closes in {duration} unless its cargo is used."),
			{ duration = util.formatDurationWithCurrentCalenderSpeed(f.closesIn or 0, speed.millisPerDay) })
	end
	return nil
end

---@param v? number
---@return string
local function percent(v) return api.util.toStringPercentPrecision(v or 0, 0) end

-- Cards -------------------------------------------------------------------------------------------------

-- One row of the card: a label on the left (fixed width, so the values line up) and its value.
---@param label string
---@param value react.TreeNodeId
---@param tooltip? string
---@return react.TreeNodeId
local function row(label, value, tooltip)
	return builtin.BoxLayout{
		meta = { class = "uio-industry-row" },
		orientation = builtin.type.Orientation.Horizontal,
		children = { text(label, "font-scale-body, uio-industry-label", tooltip), value },
	}
end

---@param fraction? number
---@param label string
---@param tooltip? string
---@return react.TreeNodeId
local function bar(fraction, label, tooltip)
	return builtin.ProgressBar{
		meta = { class = "font-scale-annotation, uio-industry-bar", tooltip = tooltip },
		value = math.max(0, math.min(1, fraction or 0)),
		label = label,
	}
end

-- "[icon] 11 + [icon] 7 -> [icon] 4" with the game's cargo icons; each output icon's tooltip says how
-- much of it the industry can make per year, and a single output says it in the row as well.
---@param recipe uo.industry_cards.Recipe
---@return react.TreeNodeId
local function recipe_node(recipe)
	local children = {} ---@type react.TreeNodeId[]
	---@param amount integer
	---@return string
	local function per_year_text(amount)
		return lang_util.format(_("up to {amount} per year"), { amount = lang_util.formatInt(amount) })
	end
	---@param list uo.industry_cards.Amount[]
	---@param outputs boolean
	local function amounts(list, outputs)
		for i, entry in ipairs(list) do
			if i > 1 then children[#children + 1] = text("+", "font-scale-body, uio-industry-op") end
			local modifier = outputs and (entry[3] or 0) > 0
				and function(tooltip) return tooltip .. ": " .. per_year_text(entry[3]) end or nil
			children[#children + 1] = cargo_react_util.makeCargoIcon(entry[1], "uio-industry-cargo", nil, false, false,
				modifier)
			children[#children + 1] = text(lang_util.formatInt(entry[2]), "font-scale-body")
		end
	end
	if #recipe.inputs > 0 then
		amounts(recipe.inputs, false)
		children[#children + 1] = text("\xE2\x86\x92", "font-scale-body, uio-industry-op")
	end
	amounts(recipe.outputs, true)
	if #recipe.outputs == 1 and (recipe.outputs[1][3] or 0) > 0 then
		children[#children + 1] = text(per_year_text(recipe.outputs[1][3]), "font-scale-annotation, uio-industry-per-year")
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end

-- The Development card's content; `f` from industry_cards.read, or nil.
---@param params uo.industry_cards.CardParams
---@param f? uo.industry_cards.Facts
---@param show boolean
---@return react.TreeNodeId
local function render_development(params, f, show)
	if not f then return vertical{} end
	local growing = f.level < f.maxLevel
	local children = {} ---@type react.TreeNodeId[]
	for i, recipe in ipairs(f.recipes) do
		children[#children + 1] = row(i == 1 and _("Production") or "", recipe_node(recipe))
	end
	if growing then
		children[#children + 1] = row(_("Level"), bar(f.level / f.maxLevel,
			lang_util.formatInt(f.level) .. " / " .. lang_util.formatInt(f.maxLevel)))
	end
	if f.output > 0 then
		children[#children + 1] = row(_("Transported"), bar(f.shipped / f.output,
			lang_util.format(_("{shipped} of {output} per year"),
				{ shipped = lang_util.formatInt(f.shipped), output = lang_util.formatInt(f.output) })),
			lang_util.format(_("Production rating: {rating}"), { rating = percent(f.productionRating) }))
	end
	if growing then
		local explain = _("Every half year the industry may expand, if it produces well and its output is transported.")
		children[#children + 1] = row(_("Expansion chance"),
			bar(#f.blockers == 0 and f.chance or 0, percent(#f.blockers == 0 and f.chance or 0), explain), explain)
	end
	for _i, key in ipairs(f.blockers) do
		local line = blocker_text(key, f)
		if line then
			local warn = key ~= "max_level"
			local parts = {} ---@type react.TreeNodeId[]
			if warn then
				parts[1] = builtin.ImageView{ meta = { class = "uio-industry-alert" }, path = "::/gui/statistics/icons/alert.tga",
					scaling = builtin.type.ImageViewScaling.AutoFit }
			end
			parts[#parts + 1] = text(line, warn and "font-scale-body, uio-industry-blocker" or "font-scale-body")
			if key == "blocked" then
				parts[#parts + 1] = gui_react_util.makeHorizontalSpacer()
				parts[#parts + 1] = builtin.ToggleButton{
					meta = { class = "uio-industry-area-toggle", tooltip = _("Show the blocked area on the map") },
					content = builtin.ImageView{ path = "::/gui/statistics/icons/symbol_eye_18.tga",
						scaling = builtin.type.ImageViewScaling.AutoFit },
					value = show and 1 or 0,
					onValueChange = function(value) industry_cards.set_show_blocked_area(value == 1) end,
				}
			end
			children[#children + 1] = builtin.BoxLayout{
				meta = { class = "uio-industry-row" },
				orientation = builtin.type.Orientation.Horizontal,
				children = parts,
			}
		end
	end
	return builtin.BoxLayout{ children = {
		builtin.Component{
			meta = { id = "uio.industry.development." .. tostring(params.entity) },
			layout = vertical(children, "uio-industry-development"),
		},
	} }
end

---@class uo.industry_cards.CardParams: react.Param
---@field entity Engine.Entity
---@field colliding? boolean the window's own expansion check finds something in the way

---@param params uo.industry_cards.CardParams
---@return react.TreeNodeId
local Development = react.RegisterRecipe("UioIndustryDevelopment", function(params)
	local state = engine_react_util.useStepStateTimer(function()
		local ok, facts = pcall(industry_cards.read, params.entity)
		return ok and facts or nil
	end, REFRESH)
	local showState = react.useState(show_blocked_area)
	react.onEvent(BLOCKED_AREA_EVENT, function(_e, show) showState:set(show) end)
	local ok, node = pcall(render_development, params, industry_cards.live(state:old(), params.colliding),
		showState:old())
	if ok then return node end
	report("development", node)
	return vertical{}
end)

-- The Served by card's content: entries of industry_cards.read_lines.
---@param lines uo.industry_cards.ServingLine[]
---@return react.TreeNodeId
local function render_served_by(lines)
	if #lines == 0 then
		return vertical{ text(_("No line of yours stops within reach of this industry."), "font-scale-body") }
	end
	local children = {} ---@type react.TreeNodeId[]
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
end

---@param params uo.industry_cards.CardParams
---@return react.TreeNodeId
local ServedBy = react.RegisterRecipe("UioIndustryServedBy", function(params)
	local state = engine_react_util.useStepStateTimer(function()
		local ok, lines = pcall(industry_cards.read_lines, params.entity)
		return ok and lines or {}
	end, SERVED_REFRESH)
	local ok, node = pcall(render_served_by, state:old() or {})
	if ok then return node end
	report("served by", node)
	return vertical{}
end)

---@generic T
---@param local_key string
---@param title string
---@param recipe react.Recipe<T>
---@param param T
---@param params game.gui.entity_window.eow_extension_util.IEowWidgetsExtensionParams
---@return react.TreeNodeId
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
---@param params game.gui.entity_window.industry.industry_eow.IndustryWidgetPluginParams
---@return react.TreeNodeId
function industry_cards.industry(params)
	local entity = params.entityId
	if not entity or not api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY) then
		return builtin.BoxLayout{}
	end
	return vertical({
		card("uioIndustryDevelopment", _("Development"), Development,
			{ entity = entity, colliding = params.state and params.state.failedExpansion }, params),
		card("uioIndustryServedBy", _("Served by"), ServedBy, { entity = entity }, params),
	}, "box-plugin-vertical-space")
end

-- Blocked area on the map --------------------------------------------------------------------------

--- Shows or hides the red area of a blocked expansion (all industry windows, for the session).
---@param show boolean
function industry_cards.set_show_blocked_area(show)
	show_blocked_area = show and true or false
	react.fireEvent(nil, BLOCKED_AREA_EVENT, show_blocked_area)
end

-- The base window, with its map action rendered without the red area while it is switched off.
---@param params game.gui.entity_window.view_manager.IEntityWindowParam
---@return react.TreeNodeId
local IndustryWindow = react.RegisterRecipe("IndustryWindow", function(params)
	local showState = react.useState(show_blocked_area)
	react.onEvent(BLOCKED_AREA_EVENT, function(_e, show) showState:set(show) end)
	local show = showState:old()
	local copy = guard.shallow_copy(params)
	if type(params.setActionFn) == "function" then
		---@param fn? fun(...: any): react.TreeNodeId the map action; its arguments are passed on unchanged
		---@param ... string key2
		---@return nil setActionFn returns nothing
		copy.setActionFn = function(fn, ...)
			if type(fn) ~= "function" or show then return params.setActionFn(fn, ...) end
			-- the action is declared without params; the wrapper still passes on whatever it gets
			---@diagnostic disable-next-line: redundant-parameter
			return params.setActionFn(function(...)
				strip_plots = true
				local ok, node = pcall(fn, ...)
				strip_plots = false
				if not ok then error(node, 0) end
				return node
			end, ...)
		end
	end
	return builtin.BoxLayout{ children = { react.CallOriginalRecipe(base_industry_window, copy) } }
end)

--- Called from the react-replacement-config before the UI starts.
---@param replacement_api react.ReplacementApi
function industry_cards.install(replacement_api)
	builtin_wraps.wrap("LayerConfig", function(base)
		---@param p builtin.LayerConfigParam
		---@param ... any the builtin's other arguments, passed on unchanged
		---@return react.TreeNodeId
		return function(p, ...)
			if strip_plots and select("#", ...) == 0 and type(p) == "table" and p.config ~= nil then
				pcall(function()
					p.config.plotsRenderableConfig = api.type.LayerConfig.PlotsRenderableConfig.new()
				end)
			end
			return base(p, ...)
		end
	end)
	replacement_api.ReplaceRecipe(base_industry_window, IndustryWindow)
	debugPrint("[ui_overhaul] industry blocked-area switch installed")
end

return industry_cards
