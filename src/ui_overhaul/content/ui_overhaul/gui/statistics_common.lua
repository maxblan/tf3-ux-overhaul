--- Pieces shared by the mod's statistics tabs (Lines, Vehicles, Stations): the quick filter bar
-- above the table, the 12-month balance with a short-lived cache, and the problems check.
-- @module ui_overhaul.gui.statistics_common
local builtin = require("::/gui/main/builtin.lua")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local statistics_react_util = require("::/gui/statistics/statistics_react_util.tl")

local statistics_common = {}

---@class uo.statistics_common.QuickFilter
---@field key string
---@field label string

---@class uo.statistics_common.QuickFilterBarOpts
---@field filters uo.statistics_common.QuickFilter[]
---@field selected string
---@field onSelect fun(key: string)
---@field tagPrefix string
---@field totalsId string
---@field totalsText string
---@field amountLabel string
---@field amount integer
---@field amountClass? string
---@field extra? react.TreeNodeId

---@return integer
local function game_time()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

--- Balance of the last 12 months, as the statistics "Balance" columns show it. Reads only the engine.
---@param entity Engine.Entity
---@return integer
function statistics_common.balance(entity)
	local gameTime = game_time()
	local fromTime = math.max(gameTime - api.util.getDefaultYearDuration(), 0)
	return api.engine.util.finance.calculateBalance({ entity }, fromTime, gameTime, true)
end

--- A cached statistics_common.balance: values are reused for one second of game time, so quick
-- filters and totals do not query the journal every frame. Reads only the engine.
---@return fun(entity: Engine.Entity): integer
function statistics_common.makeBalanceCache()
	---@type { time: integer, values: table<Engine.Entity, integer> }
	local cache = { time = -1, values = {} }
	return function(entity)
		local gameTime = game_time()
		if gameTime - cache.time > 1000 or gameTime < cache.time then
			cache.time, cache.values = gameTime, {}
		end
		local value = cache.values[entity]
		if value == nil then
			value = statistics_common.balance(entity)
			cache.values[entity] = value
		end
		return value
	end
end

--- True if the entity has active problem notifications.
-- getProblemsCompareValue returns { count, ids } (statistics_react_util.tl).
---@param notificationsState table<Engine.Entity, integer[]>?
---@param entity Engine.Entity
---@return boolean
function statistics_common.hasProblems(notificationsState, entity)
	local value = statistics_react_util.getProblemsCompareValue(notificationsState or {}, entity)
	if type(value) == "table" then return (value[1] or 0) > 0 end
	return type(value) == "number" and value > 0
end

--- Quick filters on the left, totals of the rows shown on the right, in one line above the table.
-- opts.filters      { { key = "all", label = _("All") }, ... }
-- opts.selected     key of the active filter
-- opts.onSelect     function(key)
-- opts.tagPrefix    meta tag prefix of the filter buttons (tag = prefix .. key)
-- opts.totalsId     meta id of the totals text
-- opts.totalsText   text of the totals ("3 lines, 5 vehicles")
-- opts.amountLabel  label in front of the amount ("Balance")
-- opts.amount       money value
-- opts.amountClass  style classes of the amount (default "font-scale-body")
-- opts.extra        optional node after the filters (for example a drop-down list)
---@param opts uo.statistics_common.QuickFilterBarOpts
---@return react.TreeNodeId
function statistics_common.QuickFilterBar(opts)
	---@type builtin.ToggleButtonGroupChildParam[]
	local buttons, selectedIndex = {}, 1
	for i, filter in ipairs(opts.filters) do
		buttons[i] = { content = builtin.TextView{ meta = { class = "font-scale-body" }, text = filter.label },
			meta = { tag = opts.tagPrefix .. filter.key } }
		if filter.key == opts.selected then selectedIndex = i end
	end
	return builtin.BoxLayout{
		meta = { class = "uio-statistics-quick-filters" },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.ToggleButtonGroup{
				buttons = buttons,
				selected = selectedIndex,
				onValueChange = function(index)
					local filter = opts.filters[index]
					if filter then opts.onSelect(filter.key) end
				end,
			},
			opts.extra,
			gui_react_util.makeHorizontalSpacer(),
			builtin.TextView{ meta = { class = "font-scale-body", id = opts.totalsId }, text = opts.totalsText },
			builtin.TextView{ meta = { class = "font-scale-body" }, text = opts.amountLabel },
			builtin.TextView{ meta = { class = opts.amountClass or "font-scale-body" },
				text = api.util.formatMoney(opts.amount) },
		},
	}
end

--- Style classes of a balance: red when negative, green otherwise.
---@param value number
---@return string
function statistics_common.balanceClass(value)
	return value < 0 and "font-scale-body, negative" or "font-scale-body, positive"
end

--- True if two arrays of entities are equal (faster than deepEquals for long arrays).
---@param a Engine.Entity[]?
---@param b Engine.Entity[]?
---@return boolean
function statistics_common.sameArray(a, b)
	if a == b then return true end
	if a == nil or b == nil or #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

--- True if two sets ({ [entity] = true }) are equal.
---@param a table<Engine.Entity, boolean>?
---@param b table<Engine.Entity, boolean>?
---@return boolean
function statistics_common.sameSet(a, b)
	if a == b then return true end
	if a == nil or b == nil then return false end
	for key in pairs(a) do
		if not b[key] then return false end
	end
	for key in pairs(b) do
		if not a[key] then return false end
	end
	return true
end

--- A string that changes whenever the base filter of the statistics window changes (search, carrier
-- categories, "only visible"), used to refilter at once instead of waiting for the next refresh.
---@param params game.gui.statistics.statistics.StatisticsRecipeParams
---@return string
function statistics_common.filterSignature(params)
	---@type string[]
	local categories = {}
	for index, enabled in pairs(params.filterShowCategories or {}) do
		if enabled then categories[#categories + 1] = tostring(index) end
	end
	table.sort(categories)
	return table.concat({ tostring(params.searchString), tostring(params.filterShowOnlyVisible),
		table.concat(categories, ",") }, "|")
end

return statistics_common
