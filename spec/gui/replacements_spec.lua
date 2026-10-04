-- The replacements that fall back to the base recipe (fallback.lua): each registers a parent with the
-- same hooks on every render and a child under the base name for the base stylesheet; a child keeps
-- its hooks when it renders again, and the parent shows the base once the child failed. The base
-- modules are stand-ins (fake_react.load); without an engine the renders fail, as they would after a
-- game update.
local fake_react = require("fake_react")

local PARENT_HOOKS = { "useState", "onStep", "useRef", "useRef" }

local CASES = {
	{ module = "earnings", name = "GameBarEarningsPlugin",
		base_path = "::/gui/game_bar/game_bar_display_earnings_plugin/game_bar_display_earnings.script.tl",
		field = "GameBarEarningsPlugin" },
	{ module = "finances", name = "FinancesTable", base_path = "::/game_mechanics/finance/finances_table.tl" },
	{ module = "statistics_lines", name = "LinesStatistic", base_path = "::/gui/statistics/statistic_lines.tl" },
	{ module = "statistics_stations", name = "StationsStatistic",
		base_path = "::/gui/statistics/statistic_stations.tl" },
	{ module = "statistics_vehicles", name = "VehiclesStatistic",
		base_path = "::/gui/statistics/statistic_vehicles.tl" },
	{ module = "statistics_warehouses", name = "WarehousesStatistic",
		base_path = "::/gui/statistics/statistic_warehouses.tl" },
}

-- What the specs use of each replacement module.
---@class spec.replacements.Module
---@field install fun(replacement_api: react.ReplacementApi)
---@field switch uo.gui.fallback.Switch

-- What the map editor spec's stand-in for `api` provides.
---@class spec.replacements.Api
---@field gui { game: { isMapEditor: fun(): boolean } }

describe("replacements with a fallback", function()
	local saved_debug_print = _G.debugPrint
	local function quiet() end
	before_each(function() _G.debugPrint = quiet end)
	after_each(function() _G.debugPrint = saved_debug_print end)

	for _i, case in ipairs(CASES) do
		it(case.module .. " shows its child, then the base for the session", function()
			local fake = fake_react.new()
			local base = fake.react.RegisterRecipe(case.name, function() end)
			local builtin = fake_react.any()
			builtin.BoxLayout = function(t) return { layout = t } end
			---@type spec.replacements.Module
			local module = fake_react.load("/ui_overhaul/gui/" .. case.module .. ".lua", {
				["::/gui/main/react.lua"] = fake.react,
				["::/gui/main/builtin.lua"] = builtin,
				[case.base_path] = case.field and { [case.field] = base } or base,
			})
			---@type function, function
			local replaced, replacement
			module.install({ ReplaceRecipe = function(old, new) replaced, replacement = old, new end })
			assert.are.equal(base, replaced)
			assert.are.equal(case.name, fake.react.GetRecipeName(replacement))

			local params = { declareFilterOnMount = function() end }
			local parent = fake.mount(replacement)
			local child_node = parent.render(params).layout.children[1] ---@type spec.FakeNode
			assert.are.same(PARENT_HOOKS, parent.hooks)
			assert.are.equal(case.name, child_node.name) -- the base stylesheet selects it
			assert.is_true(base ~= child_node.recipe)

			local child = fake.render_node(child_node)
			local hooks = child.hooks
			child.render(params)
			assert.are.same(hooks, child.hooks)
			assert.is_true(module.switch.failed, "renders without an engine")

			parent.step()
			local node = parent.render(params)
			assert.are.same(PARENT_HOOKS, parent.hooks)
			assert.are.equal(base, node.layout.children[1].original)
			assert.are.equal(params, node.layout.children[1].args[1])
		end)
	end

	it("earnings: renders nothing in the map editor, as the base plugin does", function()
		local fake = fake_react.new()
		local base = fake.react.RegisterRecipe("GameBarEarningsPlugin", function() end)
		local builtin = fake_react.any()
		builtin.BoxLayout = function(t) return { layout = t } end
		---@type spec.replacements.Module
		local earnings = fake_react.load("/ui_overhaul/gui/earnings.lua", {
			["::/gui/main/react.lua"] = fake.react,
			["::/gui/main/builtin.lua"] = builtin,
			["::/gui/game_bar/game_bar_display_earnings_plugin/game_bar_display_earnings.script.tl"] = {
				GameBarEarningsPlugin = base },
		})
		---@type function
		local replacement
		earnings.install({ ReplaceRecipe = function(_old, new) replacement = new end })
		local saved_api = _G.api
		---@type spec.replacements.Api
		local mock = { gui = { game = { isMapEditor = function() return true end } } }
		-- A partial stand-in (spec.replacements.Api). The cast keeps LuaLS from merging the mock's types into
		-- the global `api` everywhere else; a plain assignment would.
		_G.api = mock --[[@as api]]
		local parent = fake.mount(replacement)
		local node = parent.render()
		_G.api = saved_api
		assert.is_nil(node)
		assert.are.same(PARENT_HOOKS, parent.hooks)
	end)
end)
