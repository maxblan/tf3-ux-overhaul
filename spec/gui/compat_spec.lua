-- compat.lua: a feature is checked against everything its modules, the modules they require and its
-- plugins read from the base game; a missing field or module is named, nothing else.
_G.debugPrint = _G.debugPrint or function() end -- guard.module logs a module that does not load

local compat = require("/ui_overhaul/gui/compat.lua")

describe("compat", function()
	local loaded = package.loaded ---@type table<string, any> module name -> module, of any type

	before_each(function()
		loaded["::/spec/present.tl"] = { Recipe = function() end, helper = function() end }
		loaded["::/spec/changed.tl"] = { helper = function() end }
		compat.use({
			modules = {
				feature_module = { ["::/spec/present.tl"] = { "Recipe" } },
				shared = { ["::/spec/present.tl"] = { "helper" } },
				changed = { ["::/spec/changed.tl"] = { "Renamed", "helper" } },
				gone = { ["::/spec/no_such_module.tl"] = { "Anything" } },
				plugin = { ["::/spec/changed.tl"] = { "Plugin" } },
			},
			requires = { feature_module = { "shared" }, uses_changed = { "changed" } },
			plugins = { with_plugin = { "plugin" } },
		})
	end)
	after_each(function()
		loaded["::/spec/present.tl"], loaded["::/spec/changed.tl"] = nil, nil
		compat.use(nil)
	end)

	it("finds nothing missing while the game has every field", function()
		assert.are.same({}, compat.missing("feature_module", "feature"))
		assert.are.same({}, compat.missing("not_listed"))
	end)

	it("names a field the game no longer has, also in a module the feature requires", function()
		assert.are.same({ "::/spec/changed.tl Renamed" }, compat.missing("changed"))
		assert.are.same({ "::/spec/changed.tl Renamed" }, compat.missing("uses_changed"))
	end)

	it("names every field of a base module that no longer loads", function()
		assert.are.same({ "::/spec/no_such_module.tl Anything" }, compat.missing("gone"))
	end)

	it("only asks a base module whose fields the code does not read to load", function()
		loaded["::/spec/recipe.tl"] = function() end -- a module that is a recipe itself
		compat.use({ modules = { m = { ["::/spec/recipe.tl"] = {}, ["::/spec/gone_too.tl"] = {} } },
			requires = {}, plugins = {} })
		assert.are.same({ "::/spec/gone_too.tl" }, compat.missing("m"))
		loaded["::/spec/recipe.tl"] = nil
	end)

	it("checks what the feature's plugins render as well", function()
		assert.are.same({ "::/spec/changed.tl Plugin" }, compat.missing("feature_module", "with_plugin"))
	end)
end)
