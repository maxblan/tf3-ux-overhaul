_G.debugPrint = _G.debugPrint or function() end

-- A world of mods: the game's resources, then this mod's, then the others' in `order` (ids follow the
-- activation order, as in game). `order` lists mod ids, this mod included.
---@param order string[]
local function world(order)
	local names = {} ---@type table<integer, string>
	local configs = {} ---@type integer[]
	local plugins = {} ---@type integer[]
	for i, mod in ipairs(order) do
		local config, plugin = 99 + 2 * i, 100 + 2 * i
		names[config], names[plugin] = mod .. "::/x.res", mod .. "::/card.res"
		configs[#configs + 1], plugins[#plugins + 1] = config, plugin
	end
	local globals = _G ---@type table<string, any> the game's globals, stand-ins here
	globals._react = { extensionPoints = { ["::IndustryEowExtensionPoint"] = true }, recipeReplace = {} }
	globals.api = {
		res = { genericRep = {
			getAllOfType = function(type_name)
				if type_name == "react-replacement-config" then return configs end
				if type_name == "react-plugin ::IndustryEowExtensionPoint" then return plugins end
				return {}
			end,
			getName = function(rid) return names[rid] end,
			get = function(rid) return { data = { filePath = (names[rid]:gsub("%.res$", ".script@Card")) } } end,
		} },
	}
end

-- Recipes of a fake framework: an id per function, and the replacement registry the game keeps.
local recipe_ids = {} ---@type table<function, integer>
local recipe_names = {} ---@type table<function, string>
local recipe_count = 0
local fake_react = {
	GetRecipeId = function(fn) return recipe_ids[fn] end,
	GetRecipeName = function(fn) return recipe_names[fn] end,
	getPlugins = function(_point) return {} end,
}
---@param name string
---@return function
local function recipe(name)
	local fn = function() return name end
	recipe_count = recipe_count + 1
	recipe_ids[fn] = recipe_count
	recipe_names[fn] = name
	return fn
end

--- A fresh priority module (its state is per session in game).
---@return uo.gui.priority
local function load_priority()
	package.loaded["::/gui/main/react.lua"] = fake_react --[[@as table]]
	package.loaded["ui_overhaul_1::/ui_overhaul/gui/priority.lua"] = nil ---@type nil
	package.loaded["/ui_overhaul/gui/priority.lua"] = nil ---@type nil
	return require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")
end

--- The game's replacement api: records the final replacement per recipe.
---@return react.ReplacementApi api
---@return table<function, function?> replaced
local function game_api()
	local replaced = {} ---@type table<function, function?>
	return { ReplaceRecipe = function(original, replacement) replaced[original] = replacement end }, replaced
end

-- Code of another mod: functions whose source names that mod, as the game's require gives them.
---@param mod string
---@param code string
---@return any
local function mod_code(mod, code)
	return assert(load(code, mod .. "::/code.lua"))()
end

describe("priority", function()
	it("wraps plainly outside an install (specs, the testbench)", function()
		local priority = load_priority()
		local module = { f = function(x) return x end }
		priority.chain(module, "f", function(previous) return function(x) return previous(x) + 1 end end)
		assert.are.equal(2, module.f(1))
		assert.is_true(priority.active("anything"))
	end)

	it("reads the activation order from the resource ids", function()
		world({ "first_mod", "ui_overhaul_1", "later_mod" })
		local priority = load_priority()
		priority.early(game_api(), function() return true end)
		assert.is_true(priority.comes_first("first_mod"))
		assert.is_false(priority.comes_first("later_mod"))
		assert.is_nil(priority.comes_first("inactive_mod"))
	end)

	describe("a recipe both replace", function()
		local finances_table = recipe("FinancesTable")
		local ours, theirs = recipe("Ours"), recipe("Theirs")

		---@param order string[]
		---@return uo.gui.priority priority
		---@return table<function, function?> replaced
		local function run(order)
			world(order)
			local priority = load_priority()
			local api_, replaced = game_api()
			priority.early(api_, function() return true end)
			priority.begin("finances", true)
			priority.replacement_api(api_).ReplaceRecipe(finances_table, ours)
			priority.finish(true)
			-- the other mod's config, after this mod's early one
			local other = mod_code("other_mod", "return function(api, a, b) api.ReplaceRecipe(a, b) end")
			other(api_, finances_table, theirs)
			priority.late()
			return priority, replaced
		end

		it("is this mod's when it comes first", function()
			local priority, replaced = run({ "ui_overhaul_1", "other_mod" })
			assert.are.equal(ours, replaced[finances_table])
			assert.is_true(priority.active("finances"))
			assert.is_false(priority.outranked("finances"))
		end)

		it("is the other mod's when that one comes first, and the feature is off", function()
			local priority, replaced = run({ "other_mod", "ui_overhaul_1" })
			assert.are.equal(theirs, replaced[finances_table])
			assert.is_false(priority.active("finances"))
			assert.are.equal("other_mod", priority.winner("finances"))
		end)
	end)

	describe("a function both wrap", function()
		---@param order string[]
		---@return uo.gui.priority priority
		---@return { f: fun(x: string): string } module
		local function run(order)
			world(order)
			local priority = load_priority()
			local api_ = game_api()
			local module = { f = function(x) return x end }
			priority.early(api_, function() return true end)
			priority.begin("feature", true)
			priority.chain(module, "f", function(previous) return function(x) return previous(x) .. " ours" end end)
			priority.finish(true)
			mod_code("other_mod", [[return function(module)
				local previous = module.f
				module.f = function(x) return previous(x) .. " theirs" end
			end]])(module)
			priority.late()
			return priority, module
		end

		it("keeps both; this mod's wrap is outermost (has the last word) when it comes first", function()
			local priority, module = run({ "ui_overhaul_1", "other_mod" })
			assert.are.equal("x theirs ours", module.f("x"))
			assert.is_false(priority.outranked("feature"))
		end)

		it("keeps both; the other mod's wrap is outermost when that one comes first", function()
			local priority, module = run({ "other_mod", "ui_overhaul_1" })
			assert.are.equal("x ours theirs", module.f("x"))
			assert.is_true(priority.active("feature"))
			assert.is_true(priority.outranked("feature"))
		end)

		it("passes through when the feature is switched off", function()
			world({ "ui_overhaul_1" })
			local priority = load_priority()
			local module = { f = function(x) return x end }
			priority.early(game_api(), function() return false end)
			priority.begin("feature", false)
			-- (the installer does not install a switched-off feature; were it installed, its link is off)
			priority.chain(module, "f", function(previous) return function(x) return previous(x) .. " ours" end end)
			priority.finish(true)
			priority.late()
			assert.are.equal("x", module.f("x"))
			assert.is_false(priority.active("feature"))
		end)

		it("leaves a widget function many mods wrap (generic) innermost, without a conflict", function()
			world({ "ui_overhaul_1", "other_mod" })
			local priority = load_priority()
			local module = { f = function(x) return x end }
			priority.early(game_api(), function() return true end)
			priority.begin("feature", true)
			priority.chain(module, "f", function(previous) return function(x) return previous(x) .. " ours" end end, true)
			priority.finish(true)
			local previous = module.f
			module.f = function(x) return previous(x) .. " theirs" end
			priority.late()
			assert.are.equal("x ours theirs", module.f("x"))
		end)
	end)

	it("takes back what a module did before its install failed; modules installed in full stay", function()
		world({ "ui_overhaul_1" })
		local priority = load_priority()
		local api_, replaced = game_api()
		local a, b = recipe("A"), recipe("B")
		local module = { f = function(x) return x end }
		priority.early(api_, function() return true end)
		priority.begin("statistics", true) -- the first module installs in full
		priority.replacement_api(api_).ReplaceRecipe(a, recipe("A2"))
		priority.finish(true)
		priority.begin("statistics", true) -- the second fails after a replacement and a wrap
		priority.replacement_api(api_).ReplaceRecipe(b, recipe("B2"))
		priority.chain(module, "f", function(previous) return function(x) return previous(x) .. " half" end end)
		priority.finish(false)
		priority.late()
		assert.is_true(priority.active("statistics"))
		assert.is_true(replaced[a] ~= nil)
		assert.is_nil(replaced[b])
		assert.are.equal("x", module.f("x"))
	end)

	describe("a mod that duplicates a feature (OVERLAPS)", function()
		it("holds it back when this mod comes first", function()
			world({ "ui_overhaul_1", "gleisbauanzeige_tf3" })
			local construction_react_util = {}
			package.loaded["::/gui/construction/construction_react_util.tl"] = construction_react_util
			local priority = load_priority()
			priority.early(game_api(), function() return true end)
			assert.is_true(construction_react_util.__gleisbauanzeigeInstalled)
		end)

		it("gives way to it when it comes first", function()
			world({ "cayde_industry_enhanced_1", "ui_overhaul_1" })
			local priority = load_priority()
			priority.early(game_api(), function() return true end)
			priority.begin("industry", true)
			priority.finish(true)
			priority.late()
			assert.is_false(priority.active("industry"))
			assert.are.equal("cayde_industry_enhanced_1", priority.winner("industry"))
		end)

		it("does not hold it back when the feature is switched off", function()
			world({ "ui_overhaul_1", "gleisbauanzeige_tf3" })
			local construction_react_util = {}
			package.loaded["::/gui/construction/construction_react_util.tl"] = construction_react_util
			local priority = load_priority()
			priority.early(game_api(), function(feature) return feature ~= "build_info" end)
			assert.is_nil(construction_react_util.__gleisbauanzeigeInstalled)
		end)

		it("leaves its plugins out of the extension point when this mod comes first", function()
			world({ "ui_overhaul_1", "cayde_industry_enhanced_1" })
			local own_card, their_card = function() end, function() end
			package.loaded["::/scripts/util.tl"] = { useFn = function(path)
				return path:find("^cayde_industry_enhanced_1::") and their_card or nil
			end }
			---@param _point { id: string }?
			---@return { recipe: function }[]
			fake_react.getPlugins = function(_point) return { { recipe = own_card }, { recipe = their_card } } end
			local priority = load_priority()
			priority.early(game_api(), function() return true end)
			priority.begin("industry", true)
			priority.finish(true)
			priority.late()
			priority.filter_plugins()
			local shown = fake_react.getPlugins({ id = "::IndustryEowExtensionPoint" })
			assert.are.same({ { recipe = own_card } }, shown)
			assert.are.equal(2, #fake_react.getPlugins({ id = "::LineEowExtensionPoint" }))
		end)

		it("keeps its plugins when this mod's feature ends up off (an install that failed)", function()
			world({ "ui_overhaul_1", "cayde_industry_enhanced_1" })
			local their_card = function() end
			package.loaded["::/scripts/util.tl"] = { useFn = function() return their_card end }
			---@param _point { id: string }?
			---@return { recipe: function }[]
			fake_react.getPlugins = function(_point) return { { recipe = their_card } } end
			local priority = load_priority()
			priority.early(game_api(), function() return true end)
			priority.begin("industry", true)
			priority.finish(false)
			priority.late()
			priority.filter_plugins()
			assert.are.equal(1, #fake_react.getPlugins({ id = "::IndustryEowExtensionPoint" }))
		end)
	end)
end)
