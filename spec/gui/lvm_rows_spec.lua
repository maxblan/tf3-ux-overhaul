-- lvm_rows.lua: how a Line Manager vehicle row reads its lifespan, and that a row declares its hook
-- when reading fails. The base modules it requires are stand-ins; only the pure helpers run. Which
-- cargo icons a line row shows: line_cargo_spec.lua.

package.loaded["::/gui/main/react.lua"] = { RegisterRecipe = function(_name, fn) return fn end }
package.loaded["::/gui/main/builtin.lua"] = package.loaded["::/gui/main/builtin.lua"] or {} -- render only
package.loaded["::/gui/main/engine_react_util.tl"] = {}
package.loaded["::/gui/line_vehicle_mgmt/line_react_util.tl"] = {}
package.loaded["::/gui/line_vehicle_mgmt/vehicle_util.tl"] = {}
package.loaded["::/scripts/lang_util.tl"] = {}
package.loaded["::/gui/main/cargo_react_util.tl"] = {}
package.loaded["::/gui/main/cargo_util.tl"] = {}

local saved_api = _G.api

describe("lvm_rows lifetime", function()
	local lvm_rows_module ---@type uo.gui.lvm_rows
	before_each(function() lvm_rows_module = require("/ui_overhaul/gui/lvm_rows.lua") end)

	it("gives the share of the lifespan used until it is reached", function()
		local reached, used = lvm_rows_module.lifetime(1000, 4000, 2000)
		assert.is_false(reached)
		assert.are.equal(0.25, used)
		assert.is_true((lvm_rows_module.lifetime(1000, 4000, 5000)))
		assert.is_true((lvm_rows_module.lifetime(1000, 4000, 9000)))
	end)

	it("counts a model without a lifespan as reached, like the base age cell, and divides by nothing", function()
		for _i, now in ipairs({ 1000, 1500, 999999 }) do
			local reached, used = lvm_rows_module.lifetime(1000, 0, now)
			assert.is_true(reached)
			assert.is_nil(used)
		end
	end)
end)

describe("lvm_rows row info hooks", function()
	local fake_react = require("fake_react")
	local fake = fake_react.new()
	local builtin = fake_react.any()
	builtin.BoxLayout = function(t) return { layout = t } end
	fake_react.load("/ui_overhaul/gui/lvm_rows.lua", {
		["::/gui/main/react.lua"] = fake.react,
		["::/gui/main/builtin.lua"] = builtin,
		-- as the game's hook: declared once its callback returned (useStateLazy calls it)
		["::/gui/main/engine_react_util.tl"] = {
			---@param fn fun(old?: uo.gui.lvm_rows.Data): uo.gui.lvm_rows.Data? the row's read callback
			---@return { old: fun(): uo.gui.lvm_rows.Data? }
			useStepStateTimer = function(fn)
				local value = fn(nil)
				fake.hook("useStepStateTimer")
				return { old = function() return value end }
			end,
		},
	})

	it("declares its hook even when reading the row fails", function()
		_G.api = nil -- reading raises
		local row = fake.mount(fake.recipe("UioLvmRowInfo"))
		local node = row.render(7)
		assert.are.same({ "useStepStateTimer" }, row.hooks)
		assert.are.same({}, node.layout.children)
		_G.api = saved_api
	end)
end)
