-- lvm_rows.lua: which cargo icons a Line Manager line row shows. The base modules it requires are
-- stand-ins; only the cargo helpers run.
local PASSENGERS = 0
local sorted -- what the stand-in cargo_util.getSortedProducedCargoTypes returns
local stops -- the stand-in LINE component's stops
local produced -- cargo type ids the stand-in reports as currently produced

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
local lvm_rows

local function stop(...)
	local load = {}
	for i = 1, 6 do load[i] = false end
	for _i, id in ipairs({ ... }) do load[id + 1] = true end
	return { stopConfig = { load = load } }
end

describe("lvm_rows cargo", function()
	before_each(function()
		sorted, stops, produced = {}, {}, { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
		_G.api = {
			type = { ComponentType = { LINE = "LINE" } },
			engine = {
				getComponent = function(_entity, kind) return kind == "LINE" and { stops = stops } or nil end,
				util = { stock = { isCargoTypeCurrentlyProduced = function(id) return produced[id] == true end } },
			},
		}
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
