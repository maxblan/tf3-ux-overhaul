-- guard.lua needs the base builtin module; a stand-in records what would be rendered.
package.loaded["::/gui/main/builtin.lua"] = { BoxLayout = function() return "empty" end }
package.loaded["/fixtures/ok.lua"] = { render = function(x) return "rendered " .. x end }
package.loaded["/fixtures/broken.lua"] = { render = function() error("boom") end }
_G.debugPrint = _G.debugPrint or function() end

local guard = require("/ux_overhaul/gui/guard.lua")

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
end)
