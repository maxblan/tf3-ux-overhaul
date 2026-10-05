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
	globals._ug_loadedModules = {} -- the loader's registry of modules loaded with require (base/init.lua)
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

--- The game's replacement api: sets the replacement in the registry the game keeps (_react.recipeReplace,
-- by recipe id), as GloballyReplaceRecipeBeforeInitInternal does.
---@return react.ReplacementApi api
---@return table<function, function?> replaced the replacement per recipe, read from that registry
local function game_api()
	local replaced = setmetatable({}, { __index = function(_t, original)
		return _react.recipeReplace[recipe_ids[original]]
	end }) ---@type table<function, function?>
	return { ReplaceRecipe = function(original, replacement)
		_react.recipeReplace[recipe_ids[original]] = replacement
	end }, replaced
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
		local module = { f = function(x) return x end, g = function(x) return x end }
		priority.early(api_, function() return true end)
		priority.begin("statistics", true) -- the first module installs in full
		priority.replacement_api(api_).ReplaceRecipe(a, recipe("A2"))
		priority.finish(true)
		priority.begin("statistics", true) -- the second fails after a replacement, a wrap and a widget wrap
		priority.replacement_api(api_).ReplaceRecipe(b, recipe("B2"))
		priority.chain(module, "f", function(previous) return function(x) return previous(x) .. " half" end end)
		priority.chain(module, "g", function(previous) return function(x) return previous(x) .. " half" end end, true)
		priority.finish(false)
		priority.late()
		assert.is_true(priority.active("statistics"))
		assert.is_true(replaced[a] ~= nil)
		assert.is_nil(replaced[b])
		assert.are.equal("x", module.f("x"))
		assert.are.equal("x", module.g("x"))
	end)

	describe("settles every switch once the order is decided", function()
		---@param x string
		---@return string
		local function original(x) return x end
		---@param previous fun(x: string): string
		---@return fun(x: string): string
		local function ours(previous) return function(x) return previous(x) .. " ours" end end

		it("puts the wrap itself in the field, or the function it wrapped where the feature is off", function()
			world({ "ui_overhaul_1" })
			local priority = load_priority()
			local on, off = { f = original }, { f = original }
			priority.early(game_api(), function(feature) return feature == "on" end)
			priority.begin("on", true)
			local slot = priority.chain(on, "f", ours)
			priority.finish(true)
			priority.begin("off", false)
			priority.chain(off, "f", ours)
			priority.finish(true)
			priority.late()
			assert.is_true(slot ~= on.f)
			assert.are.equal("x ours", on.f("x"))
			assert.are.equal(original, off.f)
		end)

		it("leaves the switch under another mod's wrap (no debug.setupvalue in the game)", function()
			world({ "ui_overhaul_1", "other_mod" })
			local priority = load_priority()
			local module = { f = original }
			local told = {} ---@type function[]
			priority.early(game_api(), function() return true end)
			priority.begin("feature", true)
			local slot = priority.chain(module, "f", ours, true, function(_old, new) told[#told + 1] = new end)
			priority.finish(true)
			mod_code("other_mod", [[return function(module)
				local previous = module.f
				module.f = function(x) return previous(x) .. " theirs" end
			end]])(module)
			priority.late()
			assert.are.equal("x ours theirs", module.f("x"))
			assert.are.equal(0, #told)
			local found = false
			for n = 1, 10 do
				local _name, value = debug.getupvalue(module.f, n)
				found = found or slot == value
			end
			assert.is_true(found)
		end)

		it("builds this mod's own links on one function anew from below, and tells who asked", function()
			for _i, a_on in ipairs({ true, false }) do
				world({ "ui_overhaul_1" })
				local priority = load_priority()
				local module = { f = original }
				local told = {} ---@type function[]
				priority.early(game_api(), function(feature) return feature == "b" or a_on end)
				priority.begin("a", a_on)
				local a_slot = priority.chain(module, "f", function(previous)
					return function(x) return previous(x) .. " a" end
				end)
				priority.finish(true)
				priority.begin("b", true)
				priority.chain(module, "f", function(previous) return function(x) return previous(x) .. " b" end end,
					false, function(_old, new) told[#told + 1] = new end)
				priority.finish(true)
				priority.late()
				assert.are.equal(a_on and "x a b" or "x b", module.f("x"))
				assert.are.same({ module.f }, told)
				for n = 1, 10 do
					local _name, value = debug.getupvalue(module.f, n)
					assert.is_true(value ~= a_slot)
				end
			end
		end)

		it("settles two features' wraps of the same function and an outer link", function()
			world({ "ui_overhaul_1", "other_mod" })
			local priority = load_priority()
			local module = { f = original }
			priority.early(game_api(), function() return true end)
			priority.begin("a", true)
			priority.chain(module, "f", function(previous) return function(x) return previous(x) .. " a" end end)
			priority.finish(true)
			priority.begin("b", true)
			priority.chain(module, "f", function(previous) return function(x) return previous(x) .. " b" end end, true)
			priority.finish(true)
			mod_code("other_mod", [[return function(module)
				local previous = module.f
				module.f = function(x) return previous(x) .. " theirs" end
			end]])(module)
			priority.late()
			-- a: outermost (it comes first), b: generic, innermost
			assert.are.equal("x b theirs a", module.f("x"))
		end)
	end)

	describe("a mod that duplicates a feature (OVERLAPS)", function()
		---construction_react_util as the specs fill it.
		---@class spec.priority.Construction
		---@field getActionParams fun(x: string): string
		---@field gleisbauanzeige_helper? fun(): string

		---@param x string
		---@return string
		local function action_params(x) return x end

		--- this mod's build_info wrap and Track & Road Build Info's, as its config makes it
		---@param order string[]
		---@param enabled boolean
		---@param ok? boolean the install
		---@return uo.gui.priority priority
		---@return spec.priority.Construction construction
		local function build_info(order, enabled, ok)
			world(order)
			---@type spec.priority.Construction
			local construction = { getActionParams = action_params }
			_ug_loadedModules["::/gui/construction/construction_react_util.tl"] = construction
			local priority = load_priority()
			priority.early(game_api(), function() return enabled end)
			priority.begin("build_info", enabled)
			if enabled then
				priority.chain(construction, "getActionParams",
					function(previous) return function(x) return previous(x) .. " ours" end end)
			end
			priority.finish(ok ~= false and enabled)
			priority.ready()
			mod_code("gleisbauanzeige_tf3", [[return function(construction)
				local original = construction.getActionParams
				local function report(reason) return reason end
				construction.getActionParams = function(x) report(x) return original(x) .. " theirs" end
				construction.gleisbauanzeige_helper = function() return report("helper") end
			end]])(construction)
			priority.late()
			return priority, construction
		end

		it("takes its wraps out when this mod comes first", function()
			local priority, construction = build_info({ "ui_overhaul_1", "gleisbauanzeige_tf3" }, true)
			assert.are.equal("x ours", construction.getActionParams("x"))
			assert.is_true(priority.held_back("gleisbauanzeige_tf3"))
			-- a function it added is its own, not a wrap: it stays
			local helper = assert(construction.gleisbauanzeige_helper)
			assert.are.equal("helper", helper())
		end)

		it("is held back neither when this mod's feature failed to install nor when it is off", function()
			local failed_priority, failed = build_info({ "ui_overhaul_1", "gleisbauanzeige_tf3" }, true, false)
			assert.are.equal("x theirs", failed.getActionParams("x"))
			assert.is_false(failed_priority.held_back("gleisbauanzeige_tf3"))
			local off_priority, off = build_info({ "ui_overhaul_1", "gleisbauanzeige_tf3" }, false)
			assert.are.equal("x theirs", off.getActionParams("x"))
			assert.is_false(off_priority.held_back("gleisbauanzeige_tf3"))
		end)

		it("gives way to it when it comes first", function()
			local priority, construction = build_info({ "gleisbauanzeige_tf3", "ui_overhaul_1" }, true)
			assert.are.equal("x theirs", construction.getActionParams("x"))
			assert.is_false(priority.active("build_info"))
			assert.are.equal("gleisbauanzeige_tf3", priority.winner("build_info"))
		end)

		it("leaves its wrap under a later mod's wrap (no debug.setupvalue in the game)", function()
			world({ "ui_overhaul_1", "gleisbauanzeige_tf3", "other_mod" })
			local construction = { getActionParams = action_params }
			_ug_loadedModules["::/gui/construction/construction_react_util.tl"] = construction
			local priority = load_priority()
			priority.early(game_api(), function() return true end)
			priority.begin("build_info", true)
			priority.chain(construction, "getActionParams",
				function(previous) return function(x) return previous(x) .. " ours" end end)
			priority.finish(true)
			priority.ready()
			for _i, mod in ipairs({ "gleisbauanzeige_tf3", "other_mod" }) do
				mod_code(mod, [[return function(construction, name)
					local original = construction.getActionParams
					construction.getActionParams = function(x) return original(x) .. " " .. name end
				end]])(construction, mod)
			end
			priority.late()
			-- both wraps stay, inside this mod's (which has the last word: it comes first)
			assert.are.equal("x gleisbauanzeige_tf3 other_mod ours", construction.getActionParams("x"))
			assert.is_true(priority.held_back("gleisbauanzeige_tf3"))
		end)

		it("takes back its recipe replacement and its wraps of modules it loads itself", function()
			world({ "ui_overhaul_1", "terminal_selector", "other_mod" })
			local station_group, theirs, other = recipe("StationGroupWindowContent"), recipe("Theirs"), recipe("Other")
			local window = recipe("Window")
			local priority = load_priority()
			local api_, replaced = game_api()
			priority.early(api_, function() return true end)
			priority.begin("station_terminals", true)
			priority.finish(true)
			priority.ready()
			-- a module loaded by its config, after this mod's installs: its own function, then their wrap
			---@type { call: fun(r: function): function }
			local late_module = assert(load("return { call = function(r) return r end }", "::/gui/main/late.lua"))()
			_ug_loadedModules["::/gui/main/late.lua"] = late_module
			mod_code("other_mod", "return function(api, a, b) api.ReplaceRecipe(a, b) end")(api_, window, other)
			mod_code("terminal_selector", [[return function(api, module, original, replacement, window, theirs)
				api.ReplaceRecipe(original, replacement)
				api.ReplaceRecipe(window, theirs)
				local call = module.call
				module.call = function(r) if r == original then return replacement end return call(r) end
			end]])(api_, late_module, station_group, theirs, window, theirs)
			priority.late()
			assert.is_nil(replaced[station_group])
			-- the replacement it made over another mod's: that one is used again
			assert.are.equal(other, replaced[window])
			assert.are.equal(station_group, late_module.call(station_group))
		end)

		it("leaves its plugins out of every extension point when this mod comes first", function()
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
			priority.ready()
			priority.late()
			local shown = fake_react.getPlugins({ id = "::IndustryEowExtensionPoint" })
			assert.are.same({ { recipe = own_card } }, shown)
			-- an extension point where it has no plugins: all stay
			assert.are.equal(2, #fake_react.getPlugins({ id = "::LineEowExtensionPoint" }))
		end)

		it("keeps its plugins when this mod's feature ends up off (an install that failed)", function()
			world({ "ui_overhaul_1", "cayde_industry_enhanced_1" })
			local their_card = function() end
			package.loaded["::/scripts/util.tl"] = { useFn = function() return their_card end }
			---@param _point { id: string }?
			---@return { recipe: function }[]
			local get_plugins = function(_point) return { { recipe = their_card } } end
			fake_react.getPlugins = get_plugins
			local priority = load_priority()
			priority.early(game_api(), function() return true end)
			priority.begin("industry", true)
			priority.finish(false)
			priority.ready()
			priority.late()
			assert.are.equal(get_plugins, fake_react.getPlugins)
		end)
	end)
end)
