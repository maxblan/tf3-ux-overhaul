-- lvm_rows.lua: which cargo icons a Line Manager line row shows and how a vehicle row reads its
-- lifespan. The base modules it requires are stand-ins; only the pure helpers run.
---@class spec.lvm_rows.Stop the stand-in LINE component's stop: what cargo_types reads
---@field stopConfig { load: boolean[] }

-- What the specs' stand-in for `api` provides: only what lvm_rows.cargo_types reads.
---@class spec.lvm_rows.Api
---@field type { ComponentType: { LINE: string } }
---@field engine spec.lvm_rows.Engine

---@class spec.lvm_rows.Engine
---@field getComponent fun(entity: integer, kind: string): { stops: spec.lvm_rows.Stop[] }?
---@field util { stock: { isCargoTypeCurrentlyProduced: fun(id: integer): boolean } }

local PASSENGERS = 0
local sorted ---@type integer[] what the stand-in cargo_util.getSortedProducedCargoTypes returns
local stops ---@type spec.lvm_rows.Stop[] the stand-in LINE component's stops
local produced ---@type table<integer, boolean> cargo type ids the stand-in reports as currently produced

package.loaded["::/gui/main/react.lua"] = { RegisterRecipe = function(_name, fn) return fn end }
package.loaded["::/gui/main/builtin.lua"] = package.loaded["::/gui/main/builtin.lua"] or {} -- render only
package.loaded["::/gui/main/engine_react_util.tl"] = {}
package.loaded["::/gui/line_vehicle_mgmt/line_react_util.tl"] = {}
package.loaded["::/gui/line_vehicle_mgmt/vehicle_util.tl"] = {}
package.loaded["::/scripts/lang_util.tl"] = {}
package.loaded["::/gui/main/cargo_react_util.tl"] = {}
package.loaded["::/gui/main/cargo_util.tl"] = {
	getSortedProducedCargoTypes = function() return sorted end,
	getPassengerCargoTypeId = function() return PASSENGERS end,
}

local saved_api = _G.api
local lvm_rows ---@type uo.gui.lvm_rows

---@param ... integer cargo type ids the stop loads
---@return spec.lvm_rows.Stop
local function stop(...)
	local load = {} ---@type boolean[]
	for i = 1, 6 do load[i] = false end
	for _i, id in ipairs({ ... }) do load[id + 1] = true end
	return { stopConfig = { load = load } }
end

describe("lvm_rows cargo", function()
	before_each(function()
		sorted, stops, produced = {}, {}, { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
		---@type spec.lvm_rows.Api
		local mock = {
			type = { ComponentType = { LINE = "LINE" } },
			engine = {
				getComponent = function(_entity, kind) return kind == "LINE" and { stops = stops } or nil end,
				util = { stock = { isCargoTypeCurrentlyProduced = function(id) return produced[id] == true end } },
			},
		}
		-- A partial stand-in (spec.lvm_rows.Api). The cast keeps LuaLS from merging the mock's types into
		-- the global `api` everywhere else; a plain assignment would.
		_G.api = mock --[[@as api]]
		lvm_rows = lvm_rows or require("/ui_overhaul/gui/lvm_rows.lua")
	end)

	after_each(function() _G.api = saved_api end)

	it("uses the cargo of the line's vehicles when there is any", function()
		sorted = { 0, 3 }
		stops = { stop(1) }
		assert.are.same({ 0, 3 }, lvm_rows.cargo_types(7))
	end)

	it("falls back to what the stops load, passengers first, each type once", function()
		stops = { stop(3, 1), stop(1, 0) }
		assert.are.same({ 0, 1, 3 }, lvm_rows.cargo_types(7))
	end)

	it("skips cargo types that are not produced and shows nothing for an unconfigured line", function()
		produced[3] = nil
		stops = { stop(3, 2) }
		assert.are.same({ 2 }, lvm_rows.cargo_types(7))
		stops = { stop(), stop() }
		assert.are.same({}, lvm_rows.cargo_types(7))
	end)

	it("shows up to three icons and puts the rest behind +N in the last slot", function()
		local shown, more = lvm_rows.cargo_slots({ 0, 1, 2 }, 3)
		assert.are.same({ 0, 1, 2 }, shown)
		assert.are.same({}, more)
		shown, more = lvm_rows.cargo_slots({ 0, 1, 2, 3, 4 }, 3)
		assert.are.same({ 0, 1 }, shown)
		assert.are.same({ 2, 3, 4 }, more)
		shown, more = lvm_rows.cargo_slots({}, 3)
		assert.are.same({}, shown)
		assert.are.same({}, more)
	end)
end)

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
