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

describe("replacements with a fallback", function()
	local saved_debug_print = _G.debugPrint
	before_each(function() _G.debugPrint = function() end end)
	after_each(function() _G.debugPrint = saved_debug_print end)

	for _i, case in ipairs(CASES) do
		it(case.module .. " shows its child, then the base for the session", function()
			local fake = fake_react.new()
			local base = fake.react.RegisterRecipe(case.name, function() end)
			local builtin = fake_react.any()
			builtin.BoxLayout = function(t) return { layout = t } end
			local module = fake_react.load("/ui_overhaul/gui/" .. case.module .. ".lua", {
				["::/gui/main/react.lua"] = fake.react,
				["::/gui/main/builtin.lua"] = builtin,
				[case.base_path] = case.field and { [case.field] = base } or base,
			})
			local replaced, replacement
			module.install({ ReplaceRecipe = function(old, new) replaced, replacement = old, new end })
			assert.are.equal(base, replaced)
			assert.are.equal(case.name, fake.react.GetRecipeName(replacement))

			local params = { declareFilterOnMount = function() end }
			local parent = fake.mount(replacement)
			local child_node = parent.render(params).layout.children[1]
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
end)
