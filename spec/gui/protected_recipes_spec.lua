-- Recipes of the mod's own cards: their hooks come first, their callbacks catch errors, and a body that
-- fails renders an empty layout (or the base card) instead of letting the error drop the game UI.
-- The base modules are stand-ins (fake_react.load); the hook stand-ins record like the game's hooks.
local fake_react = require("fake_react")

-- engine_react_util's step states: declared once their callback returned, as in the game
---@param fake spec.Fake
---@return table<string, function>
local function engine_hooks(fake)
	---@param name string
	---@return fun(fn: fun(old: nil): any): { old: fun(): any }
	local function step_state(name)
		return function(fn)
			local value = fn(nil) ---@type any the state, whatever the recipe reads
			fake.hook(name)
			return { old = function() return value end }
		end
	end
	return { useStepState = step_state("useStepState"), useStepStateTimer = step_state("useStepStateTimer") }
end

---@param path string
---@param extra? table<string, any> more module path -> stand-in, of any shape
---@return spec.Fake fake
---@return any module the loaded module, of whichever type `path` returns
local function load(path, extra)
	local fake = fake_react.new()
	local builtin = fake_react.any()
	builtin.BoxLayout = function(t) return { layout = t } end
	---@param t builtin.TextViewParam
	---@return { text: string?, meta: react.Meta? }
	builtin.TextView = function(t) return { text = t.text, meta = t.meta } end
	---@type table<string, any>
	local stand_ins = {
		["::/gui/main/react.lua"] = fake.react,
		["::/gui/main/builtin.lua"] = builtin,
		["::/gui/main/engine_react_util.tl"] = engine_hooks(fake),
	}
	for k, v in pairs(extra or {}) do stand_ins[k] = v end
	return fake, fake_react.load(path, stand_ins)
end

local EMPTY = { layout = {} }

describe("protected recipes", function()
	local globals = _G ---@type table<string, any> global name -> value, of any type
	local saved = {} ---@type table<string, any> global name -> its value before the spec
	local logged ---@type string[]
	before_each(function()
		for _i, name in ipairs({ "debugPrint", "_", "api" }) do saved[name] = globals[name] end
		logged = {}
		---@param ... any
		local function record(...) logged[#logged + 1] = table.concat({ ... }) end
		---@param text string
		---@return string
		local function tr(text) return text end
		_G.debugPrint, _G._ = record, tr
		_G.api = nil
	end)
	after_each(function()
		for name, value in pairs(saved) do globals[name] = value end
	end)

	it("industry cards: Development and Served by keep their hooks and show nothing on failure", function()
		local fake, industry_cards = load("/ui_overhaul/gui/industry_cards.lua")
		industry_cards.read = function() return { level = "odd", maxLevel = 3, recipes = {} } end
		local development = fake.mount(fake.recipe("UioIndustryDevelopment"))
		local node = development.render({ entity = 1 })
		assert.are.equal(0, #(node.layout.children or {}))
		assert.are.same({ "useStepStateTimer", "useState", "onEvent:uio.industry.blocked_area" }, development.hooks)
		industry_cards.read_lines = function() return { 5 } end
		local served = fake.mount(fake.recipe("UioIndustryServedBy"))
		assert.are.equal(0, #(served.render({ entity = 1 }).layout.children or {}))
		assert.are.same({ "useStepStateTimer" }, served.hooks)
		assert.are.equal(2, #logged)
	end)

	it("industry cards: a recorded failed expansion is no blocker once the window's check finds the way clear", function()
		local _fake, industry_cards = load("/ui_overhaul/gui/industry_cards.lua")
		local facts = { level = 1, maxLevel = 4, output = 100, chance = 0.2, blocked = true, blockers = { "blocked" } }
		assert.are.equal(facts, industry_cards.live(facts, true))
		assert.are.equal(facts, industry_cards.live(facts, nil))
		local clear = industry_cards.live(facts, false) ---@type uo.industry_cards.Facts
		assert.is_false(clear.blocked)
		assert.are.same({}, clear.blockers)
		assert.is_true(facts.blocked) -- the read facts stay as they were
	end)

	it("vehicle performance card shows nothing for odd ratings", function()
		local fake = load("/ui_overhaul/gui/performance.lua")
		local card = fake.mount(fake.recipe("UioVehiclePerformance"))
		assert.are.same(EMPTY, card.render({ entityId = 1 }))
		assert.are.same({ "useState" }, card.hooks)
		assert.are.equal(1, #logged)
	end)

	it("line vehicles card: the status cell and the card fail alone, then the base card shows", function()
		local base_card = {}
		local fake, line_vehicles = load("/ui_overhaul/gui/line_vehicles.lua", {
			["/ui_overhaul/gui/vehicle_info.lua"] = {
				read = function() return { condition = 1 } end,
				tooltip = function() return "tip" end,
				load_fraction = function() error("vehicle_info changed") end,
			},
			["/ui_overhaul/gui/actions.lua"] = { remove_refused = function() error("actions changed") end },
			["::/gui/entity_window/line/line_eow.script.tl"] = base_card,
		})
		base_card.LineVehiclesPlugin = fake.react.RegisterRecipe("LineVehiclesPlugin", function() end)

		local status = fake.mount(fake.recipe("UioLineVehicleStatus"))
		assert.are.same({}, status.render({ vehicle = 1 }).layout.children)
		assert.are.same({ "useStepStateTimer" }, status.hooks)

		local content = fake.mount(fake.recipe("UioLineVehicles"))
		_G._ = nil -- the card's texts fail
		assert.are.same(EMPTY, content.render({ line = 1 }))
		local hooks = content.hooks
		assert.are.same({ "useRef", "useStepStateTimer", "onEvent:uio.debug.line_vehicles" }, hooks)
		content.render({ line = 1 })
		assert.are.same(hooks, content.hooks)
		assert.is_true(line_vehicles.switch.failed)

		local parent = fake.mount(fake.recipe("LineVehiclesPlugin", 1))
		parent.step()
		local node = parent.render({ ownershipState = "Player", entityId = 1 })
		assert.are.same({ "useState", "onStep" }, parent.hooks)
		assert.are.equal(base_card.LineVehiclesPlugin, node.layout.children[1].original)
	end)

	it("statistics: the vehicles Age tooltip and the warehouse cells leave out what fails", function()
		local fake = load("/ui_overhaul/gui/statistics_vehicles.lua", {
			["::/gui/line_vehicle_mgmt/vehicle_util.tl"] = {
				getAge = function() return { age = "3 years", agePercent = 40, timeRemaining = "2 years" } end,
			},
		})
		local age = fake.mount(fake.recipe("VehicleAgeCell"))
		local node = age.render({ rowKey = 1 }) -- no api: the tooltip fails
		local text = node.layout.children[1] ---@type { text: string, meta: react.Meta } the stand-in TextView
		assert.are.equal("3 years", text.text)
		assert.is_nil(text.meta.tooltip)
		assert.are.same({ "useStepStateTimer" }, age.hooks)

		local wfake, warehouses = load("/ui_overhaul/gui/statistics_warehouses.lua")
		warehouses.read_cached = function() return { cargos = { { 99, 5 } } } end -- no cargo type 99
		local cell = wfake.mount(wfake.recipe("WarehouseCargoTypesCell"))
		assert.are.same(EMPTY, cell.render({ rowKey = 1 }))
		assert.are.same({ "useStepStateTimer" }, cell.hooks)
	end)
end)
