-- Recipes of the mod's own cards: their hooks come first, their callbacks catch errors, and a body that
-- fails renders an empty layout (or the base card) instead of letting the error drop the game UI.
-- The base modules are stand-ins (fake_react.load); the hook stand-ins record like the game's hooks.
local fake_react = require("fake_react")

-- engine_react_util's step states: declared once their callback returned, as in the game
local function engine_hooks(fake)
	local function step_state(name)
		return function(fn)
			local value = fn(nil)
			fake.hook(name)
			return { old = function() return value end }
		end
	end
	return { useStepState = step_state("useStepState"), useStepStateTimer = step_state("useStepStateTimer") }
end

local function load(path, extra)
	local fake = fake_react.new()
	local builtin = fake_react.any()
	builtin.BoxLayout = function(t) return { layout = t } end
	builtin.TextView = function(t) return { text = t.text, meta = t.meta } end
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
	local saved = {}
	local logged
	before_each(function()
		for _i, name in ipairs({ "debugPrint", "_", "api" }) do saved[name] = _G[name] end
		logged = {}
		_G.debugPrint = function(...) logged[#logged + 1] = table.concat({ ... }) end
		_G._ = function(text) return text end
		_G.api = nil
	end)
	after_each(function()
		for name, value in pairs(saved) do _G[name] = value end
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
		local text = node.layout.children[1]
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
