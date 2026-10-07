-- industry_cards.lua, Served by card: which lines it lists, in which order, and what each row shows
-- (the line's cargo and its rate, the Line Manager's figure). The engine is a stand-in with one
-- industry, three lines and their stations; the base modules are stand-ins (fake_react.load).
local fake_react = require("fake_react")

---@class spec.industry_cards.Line the stand-in LINE component
---@field stops { stationGroup: integer, station: integer }[]

local INDUSTRY, STOCK_LIST = 1, 2
local lines ---@type table<integer, spec.industry_cards.Line> line entity -> LINE component
local order ---@type integer[] the player's lines, in the game's order
local carried ---@type table<integer, integer[]> line entity -> cargo type ids its vehicles carry
local rates ---@type table<integer, integer> line entity -> what it can transport per year
local reaching ---@type table<integer, boolean> station entity -> its catchment reaches the industry

-- engine_react_util's step states: declared once their callback returned, as in the game
---@param fake spec.Fake
---@return table<string, function>
local function engine_hooks(fake)
	return {
		---@param fn fun(old: nil): any
		---@return { old: fun(): any }
		useStepStateTimer = function(fn)
			local value = fn(nil) ---@type any the state, whatever the recipe reads
			fake.hook("useStepStateTimer")
			return { old = function() return value end }
		end,
	}
end

---@return spec.Fake fake
---@return uo.gui.industry_cards industry_cards
local function load()
	local fake = fake_react.new()
	local builtin = fake_react.any()
	---@param t table
	---@return table
	builtin.BoxLayout = function(t) return { kind = "BoxLayout", p = t } end
	---@param t table
	---@return table
	builtin.Component = function(t) return { kind = "Component", p = t } end
	---@param t builtin.TextViewParam
	---@return table
	builtin.TextView = function(t) return { kind = "TextView", p = t } end
	local module = fake_react.load("/ui_overhaul/gui/industry_cards.lua", {
		["::/gui/main/react.lua"] = fake.react,
		["::/gui/main/builtin.lua"] = builtin,
		["::/gui/main/engine_react_util.tl"] = engine_hooks(fake),
		["::/scripts/lang_util.tl"] = {
			---@param template string
			---@param values table<string, string>
			---@return string
			format = function(template, values)
				return (template:gsub("{(%w+)}", function(name) return values[name] end))
			end,
			---@param n integer
			---@return string
			formatInt = function(n) return tostring(n) end,
		},
		["::/gui/main/cargo_react_util.tl"] = {
			---@param id integer
			---@return table
			makeCargoIcon = function(id) return { kind = "CargoIcon", id = id } end,
		},
		["::/gui/main/cargo_util.tl"] = {
			---@param param { lineEntity: integer }
			---@return integer[]
			getSortedProducedCargoTypes = function(param) return carried[param.lineEntity] or {} end,
			getPassengerCargoTypeId = function() return 0 end,
		},
	})
	return fake, module --[[@as uo.gui.industry_cards]]
end

describe("industry cards: Served by", function()
	local globals = _G ---@type table<string, any> global name -> value, of any type
	local saved = {} ---@type table<string, any> global name -> its value before the spec
	before_each(function()
		for _i, name in ipairs({ "api", "_" }) do saved[name] = globals[name] end
		---@param text string
		---@return string
		globals._ = function(text) return text end
		lines = {
			[10] = { stops = { { stationGroup = 100, station = 1 } } }, -- reaches it, carries passengers
			[11] = { stops = { { stationGroup = 101, station = 0 }, { stationGroup = 100, station = 1 } } }, -- fish
			[12] = { stops = { { stationGroup = 102, station = 0 } } }, -- does not reach it
			[13] = { stops = { { stationGroup = 100, station = 1 } } }, -- reaches it, carries its input
		}
		order = { 10, 11, 12, 13 }
		carried = { [10] = { 0 }, [11] = { 6 }, [12] = { 6 }, [13] = { 0, 5 } }
		rates = { [10] = 263, [11] = 112, [12] = 50, [13] = 947 }
		reaching = { [1001] = true }
		local groups = { [100] = { stations = { 1000, 1001 } }, [101] = { stations = { 1010 } },
			[102] = { stations = { 1020 } } }
		local stock_list = { stocks = { { cargoType = 5 } }, rules = { { output = { [6] = 1 } } } }
		local mock = {
			type = { ComponentType = { INDUSTRY = "INDUSTRY", LINE = "LINE", STATION_GROUP = "STATION_GROUP",
				STOCK_LIST = "STOCK_LIST" } },
			engine = {
				---@param entity integer
				---@param kind string
				---@return any
				getComponent = function(entity, kind)
					if kind == "INDUSTRY" then return entity == INDUSTRY and { stockList = STOCK_LIST } or nil end
					if kind == "STOCK_LIST" then return entity == STOCK_LIST and stock_list or nil end
					if kind == "LINE" then return lines[entity] end
					if kind == "STATION_GROUP" then return groups[entity] end
					return nil
				end,
				system = {
					lineSystem = { getLinesForPlayer = function() return order end },
					catchmentAreaSystem = {
						---@param station integer
						---@return integer[]
						getStationCatchables = function(station) return reaching[station] and { INDUSTRY } or {} end,
					},
				},
				util = {
					getPlayer = function() return 7 end,
					line = {
						---@param line integer
						---@return integer
						calcLineStationThroughput = function(line) return rates[line] end,
					},
					stock = { isCargoTypeCurrentlyProduced = function() return true end },
				},
			},
			res = { cargoTypeRep = { get = function() return { name = "Cargo" } end } },
		}
		-- A partial stand-in; the cast keeps LuaLS from merging the mock's types into the global `api`.
		_G.api = mock --[[@as api]]
	end)
	after_each(function()
		for name, value in pairs(saved) do globals[name] = value end
	end)

	it("lists the lines that reach the industry, those carrying its cargo first, with cargo and rate", function()
		local _fake, industry_cards = load()
		local result = industry_cards.read_lines(INDUSTRY)
		local seen = {} ---@type table[]
		for i, entry in ipairs(result) do
			seen[i] = { entry.line, entry.stop, entry.rate, entry.carries, entry.cargo }
		end
		assert.are.same({
			{ 11, 2, 112, true, { 6 } }, -- its output
			{ 13, 1, 947, true, { 0, 5 } }, -- its input
			{ 10, 1, 263, false, { 0 } },
		}, seen)
	end)

	it("keeps the game's order of the lines within each group", function()
		local _fake, industry_cards = load()
		---@param line integer
		---@param carries boolean
		---@return uo.industry_cards.ServingLine
		local function line_entry(line, carries)
			return { line = line, stop = 1, rate = 0, cargo = {}, carries = carries }
		end
		local ordered = industry_cards.order_lines({
			line_entry(1, false), line_entry(2, true), line_entry(3, false), line_entry(4, true),
		})
		local ids = {} ---@type integer[]
		for i, entry in ipairs(ordered) do ids[i] = entry.line end
		assert.are.same({ 2, 4, 1, 3 }, ids)
	end)

	it("shows each line's cargo icons and its rate per year, with the game's explanation", function()
		local fake = load()
		local served = fake.mount(fake.recipe("UioIndustryServedBy"))
		local node = served.render({ entity = INDUSTRY })
		assert.are.same({ "useStepStateTimer" }, served.hooks)
		local rows = node.p.children ---@type table[]
		assert.are.equal(3, #rows)
		local first = rows[1].p.children ---@type table[]
		assert.are.equal(4, #first)
		local icons = first[3].p.layout.p.children ---@type table[]
		assert.are.same({ "CargoIcon", 6 }, { icons[1].kind, icons[1].id })
		local rate = first[4] ---@type table
		assert.are.equal("112 per Year", rate.p.text)
		assert.are.equal("Rate: Amount of cargo or passengers a line can transport per year.", rate.p.meta.tooltip)
	end)
end)
