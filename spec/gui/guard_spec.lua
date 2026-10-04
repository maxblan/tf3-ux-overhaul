-- guard.lua needs the base builtin module; a stand-in records what would be rendered.
package.loaded["::/gui/main/builtin.lua"] = { BoxLayout = function() return "empty" end }
package.loaded["/fixtures/ok.lua"] = { render = function(x) return "rendered " .. x end }
package.loaded["/fixtures/broken.lua"] = { render = function() error("boom") end }
_G.debugPrint = _G.debugPrint or function() end

local guard = require("/ui_overhaul/gui/guard.lua")

describe("guard", function()
	it("renders through the module when it works", function()
		assert.are.equal("rendered 7", guard.plugin("/fixtures/ok.lua", "render")(7))
	end)

	it("renders an empty layout when the call fails, the module is missing or has no such function", function()
		assert.are.equal("empty", guard.plugin("/fixtures/broken.lua", "render")())
		assert.are.equal("empty", guard.plugin("/fixtures/missing.lua", "render")())
		assert.are.equal("empty", guard.plugin("/fixtures/ok.lua", "nope")())
	end)

	it("uses the given fallback", function()
		assert.is_nil(guard.call("/fixtures/broken.lua", "render", function() return nil end))
	end)

	it("loads a failing module once and puts the game loader's require stack and mod back", function()
		local globals = _G ---@type table<string, any> global name -> value, of any type
		local saved_stack, saved_mod = globals._ug_filePathRequireStack, globals._currentModIdTr
		local stack = { "base" } ---@type string[]
		globals._ug_filePathRequireStack, globals._currentModIdTr = stack, "outer"
		local attempts = 0
		-- as the game's loader does: push the path and switch the mod, then fail without undoing either
		package.preload["/fixtures/fails_once.lua"] = function()
			attempts = attempts + 1
			stack[#stack + 1] = "ui_overhaul_1::/fixtures/fails_once.lua"
			globals._currentModIdTr = "ui_overhaul_1"
			error("load failed")
		end
		assert.is_nil(guard.module("/fixtures/fails_once.lua"))
		assert.is_nil(guard.module("/fixtures/fails_once.lua"))
		assert.are.equal(1, attempts)
		assert.are.same({ "base" }, stack)
		assert.are.equal("outer", globals._currentModIdTr)
		package.preload["/fixtures/fails_once.lua"] = nil
		globals._ug_filePathRequireStack, globals._currentModIdTr = saved_stack, saved_mod
	end)

	it("reporter logs each key once with its prefix", function()
		local saved = _G.debugPrint
		local lines = {} ---@type string[]
		---@param ... any
		_G.debugPrint = function(...) lines[#lines + 1] = table.concat({ ... }) end
		local report = guard.reporter("cards: ", " failed: ")
		report("a", "boom")
		report("a", "again")
		report("b", nil)
		_G.debugPrint = saved
		assert.are.same({ "[ui_overhaul] cards: a failed: boom", "[ui_overhaul] cards: b failed: nil" }, lines)
	end)

	it("shallow_copy copies the fields, not the values", function()
		local inner = {}
		local copy = guard.shallow_copy({ x = 1, t = inner })
		assert.are.equal(1, copy.x)
		assert.are.equal(inner, copy.t)
		assert.are.equal("number", type(guard.clock()))
	end)
end)
