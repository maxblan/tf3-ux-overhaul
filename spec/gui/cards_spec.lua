-- cards.lua, line window Stops card: the waiting cells and the Waiting column's sort read what the
-- table's refresh read, so a stop removed between two refreshes is never queried. The base modules
-- it requires are stand-ins, restored after loading so other specs keep theirs.
-- A stand-in builtin: returns its params as the node, marked with `kind`.
---@param kind string
---@return fun(p?: table): table
local function node(kind) return function(p) p = p or {} p.kind = kind return p end end
local made ---@type { recipe: function, param: any }? the recipe and parameter of the line card's content
---@type table<string, table>
local stand_ins = {
	["::/gui/main/react.lua"] = {
		---@param _name string
		---@param fn function
		---@return function
		RegisterRecipe = function(_name, fn) return fn end,
		onUnmount = function() end,
	},
	["::/gui/main/builtin.lua"] = {
		BoxLayout = node("BoxLayout"), TextView = node("TextView"), DataTable = node("DataTable"),
		ColumnDesc = function(p) return p end,
		type = { Orientation = {} },
	},
	-- runs the state function once, as the first render does
	["::/gui/main/engine_react_util.tl"] = {
		---@param fn fun(): any
		---@return { old: fun(): any }
		useStepStateTimer = function(fn)
			local value = fn() ---@type any what the state function returns
			return { old = function() return value end }
		end,
	},
	["::/gui/main/content_card.tl"] = {
		ContentCard = node("ContentCard"),
		---@param recipe function
		---@param param any
		makeRecipeAndParam = function(recipe, param) made = { recipe = recipe, param = param } end,
	},
	["::/gui/main/cargo_util.tl"] = { getConfiguredStopCargoTypes = function() return { 0, 3 } end },
	["::/gui/line_vehicle_mgmt/line_react_util.tl"] = {},
	["::/gui/main/gui_react_util.tl"] = {},
	["ui_overhaul_1::/ui_overhaul/gui/guard.lua"] = { module = function() return nil end },
	["ui_overhaul_1::/ui_overhaul/core/line_problems.lua"] = {},
	["ui_overhaul_1::/ui_overhaul/gui/ui.lua"] = { ICONS = {} },
}
local loaded = package.loaded ---@type table<string, any> module name -> module, of any type
local saved = {} ---@type table<string, any> module path -> what package.loaded held: any module
for path, module in pairs(stand_ins) do
	saved[path] = loaded[path]
	loaded[path] = module
end
local cards = require("/ui_overhaul/gui/cards.lua")
for path in pairs(stand_ins) do loaded[path] = saved[path] end

local LINE = 7
local PASSENGERS, GOODS = 0, 3

-- What the spec's stand-in for `api` provides: only what the stops card reads.
---@class spec.cards.Api
---@field type { ComponentType: { LINE: string } }
---@field res { cargoTypeRep: spec.cards.CargoTypeRep }
---@field engine spec.cards.Engine

---@class spec.cards.CargoTypeRep
---@field getPassengerCargoTypeId fun(): integer
---@field get fun(id: integer): { name: string }

---@class spec.cards.Engine
---@field entityExists fun(e: integer): boolean
---@field getComponent fun(e: integer, kind: string): { stops: { stationGroup: integer }[] }
---@field util { cargo: spec.cards.UtilCargo }

---@class spec.cards.UtilCargo
---@field getCargoQualityDataAtStop fun(line: integer, index0: integer, cargo: integer): { countTotal: integer }

-- What the stand-in builtins return: their params, so the spec reads the stops table's.
---@class spec.cards.Node
---@field children? spec.cards.Node[]
---@field text? string

---@class spec.cards.Column
---@field recipe fun(p: { rowKey: integer, userParam: any }): spec.cards.Node the cells read only these
---@field getCompareValue fun(rowKey: integer): integer

---@class spec.cards.Table
---@field columns spec.cards.Column[]
---@field rowKeys integer[]
---@field userParam any the stops table's userParam, which the cells get

describe("cards: line stops", function()
	local saved_api ---@type api
	local saved_gettext ---@type fun(id: string): string
	---@type table<integer, table<integer, integer>> stop index (1-based) -> { [cargo] = waiting }
	local world

	before_each(function()
		saved_api, saved_gettext = api, _
		world = { { [PASSENGERS] = 5 }, { [PASSENGERS] = 40, [GOODS] = 2 }, { [PASSENGERS] = 1, [GOODS] = 30 } }
		---@param s string
		---@return string
		_ = function(s) return s end -- luacheck: ignore 121
		---@type spec.cards.Api
		local mock = {
			type = { ComponentType = { LINE = "line" } },
			res = { cargoTypeRep = {
				getPassengerCargoTypeId = function() return PASSENGERS end,
				get = function(id) return { name = "cargo " .. id } end,
			} },
			engine = {
				entityExists = function(e) return e == LINE end,
				getComponent = function(e, kind)
					assert(e == LINE and kind == "line")
					local stops = {} ---@type { stationGroup: integer }[]
					for i in ipairs(world) do stops[i] = { stationGroup = 100 + i } end
					return { stops = stops }
				end,
				util = { cargo = { getCargoQualityDataAtStop = function(line, index0, cargo)
					local stop = world[index0 + 1]
					assert(line == LINE and stop, "stop index out of range: " .. tostring(index0))
					return { countTotal = stop[cargo] or 0 }
				end } },
			},
		}
		-- A partial stand-in (spec.cards.Api). The cast keeps LuaLS from merging the mock's types into the
		-- global `api` everywhere else; a plain assignment would.
		api = mock --[[@as api]] -- luacheck: ignore 121
	end)
	after_each(function() api, _ = saved_api, saved_gettext end) -- luacheck: ignore 121

	-- Renders the line card's stops table: its refresh runs once. Returns the DataTable parameters.
	---@return spec.cards.Table
	local function render_table()
		-- the card reads only these two of the plugin's params
		---@diagnostic disable-next-line: missing-fields
		cards.line({ ownershipState = "Player", entityId = LINE })
		local card = assert(made, "the line card made no content")
		local layout = card.recipe(card.param) ---@type { children: spec.cards.Table[] } the stand-in BoxLayout
		return layout.children[1]
	end

	---@param table_param spec.cards.Table
	---@param index integer
	---@return string?
	local function waiting_text(table_param, index)
		local cell = table_param.columns[2].recipe{ rowKey = index, userParam = table_param.userParam }
		local text = cell.children and cell.children[1]
		return text and text.text
	end

	it("reads the waiting of every stop of the line", function()
		local count, waiting = cards.read_waiting(LINE)
		assert.are.equal(3, count)
		assert(waiting)
		assert.are.same({ passengers = 40, cargo = { { name = "cargo 3", count = 2 } }, total = 42 }, waiting[2])
		assert.is_nil(cards.read_waiting(99))
	end)

	it("sorts the Waiting column by what its cells show", function()
		local table_param = render_table()
		assert.are.same({ 1, 2, 3 }, table_param.rowKeys)
		local compare = table_param.columns[2].getCompareValue
		assert.are.same({ 5, 42, 31 }, { compare(1), compare(2), compare(3) })
		assert.are.same({ "5", "42", "31" }, { waiting_text(table_param, 1), waiting_text(table_param, 2),
			waiting_text(table_param, 3) })
		-- the Station column keeps the line order
		assert.are.equal(3, table_param.columns[1].getCompareValue(3))
	end)

	it("never queries a stop removed before the table's next refresh", function()
		local table_param = render_table()
		world[3] = nil -- the player removed the last stop; the table still has its row
		assert.are.equal("31", waiting_text(table_param, 3))
		table_param = render_table()
		assert.are.same({ 1, 2 }, table_param.rowKeys)
		assert.is_nil(waiting_text(table_param, 3))
		assert.are.equal(0, table_param.columns[2].getCompareValue(3))
	end)

	it("shows no rows once the line is gone", function()
		api.engine.entityExists = function() return false end -- luacheck: ignore 122
		assert.are.same({}, render_table().rowKeys)
	end)
end)
