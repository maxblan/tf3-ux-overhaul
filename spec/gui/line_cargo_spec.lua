-- line_cargo.lua: which cargo icons a line shows (Line Manager line rows, the industry window's Served
-- by card). The base module it requires is a stand-in.
---@class spec.line_cargo.Stop the stand-in LINE component's stop: what cargo_types reads
---@field stopConfig { load: boolean[] }

-- What the specs' stand-in for `api` provides: only what line_cargo.cargo_types reads.
---@class spec.line_cargo.Api
---@field type { ComponentType: { LINE: string } }
---@field engine spec.line_cargo.Engine

---@class spec.line_cargo.Engine
---@field getComponent fun(entity: integer, kind: string): { stops: spec.line_cargo.Stop[] }?
---@field util { stock: { isCargoTypeCurrentlyProduced: fun(id: integer): boolean } }

local PASSENGERS = 0
local sorted ---@type integer[] what the stand-in cargo_util.getSortedProducedCargoTypes returns
local stops ---@type spec.line_cargo.Stop[] the stand-in LINE component's stops
local produced ---@type table<integer, boolean> cargo type ids the stand-in reports as currently produced

package.loaded["::/gui/main/cargo_util.tl"] = {
	getSortedProducedCargoTypes = function() return sorted end,
	getPassengerCargoTypeId = function() return PASSENGERS end,
}

local saved_api = _G.api
local line_cargo ---@type uo.gui.line_cargo

---@param ... integer cargo type ids the stop loads
---@return spec.line_cargo.Stop
local function stop(...)
	local load = {} ---@type boolean[]
	for i = 1, 6 do load[i] = false end
	for _i, id in ipairs({ ... }) do load[id + 1] = true end
	return { stopConfig = { load = load } }
end

describe("line_cargo", function()
	before_each(function()
		sorted, stops, produced = {}, {}, { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
		---@type spec.line_cargo.Api
		local mock = {
			type = { ComponentType = { LINE = "LINE" } },
			engine = {
				getComponent = function(_entity, kind) return kind == "LINE" and { stops = stops } or nil end,
				util = { stock = { isCargoTypeCurrentlyProduced = function(id) return produced[id] == true end } },
			},
		}
		-- A partial stand-in (spec.line_cargo.Api). The cast keeps LuaLS from merging the mock's types into
		-- the global `api` everywhere else; a plain assignment would.
		_G.api = mock --[[@as api]]
		line_cargo = line_cargo or require("/ui_overhaul/gui/line_cargo.lua")
	end)

	after_each(function() _G.api = saved_api end)

	it("uses the cargo of the line's vehicles when there is any", function()
		sorted = { 0, 3 }
		stops = { stop(1) }
		assert.are.same({ 0, 3 }, line_cargo.cargo_types(7))
	end)

	it("falls back to what the stops load, passengers first, each type once", function()
		stops = { stop(3, 1), stop(1, 0) }
		assert.are.same({ 0, 1, 3 }, line_cargo.cargo_types(7))
	end)

	it("skips cargo types that are not produced and shows nothing for an unconfigured line", function()
		produced[3] = nil
		stops = { stop(3, 2) }
		assert.are.same({ 2 }, line_cargo.cargo_types(7))
		stops = { stop(), stop() }
		assert.are.same({}, line_cargo.cargo_types(7))
	end)

	it("shows up to three icons and puts the rest behind +N in the last slot", function()
		local shown, more = line_cargo.cargo_slots({ 0, 1, 2 }, 3)
		assert.are.same({ 0, 1, 2 }, shown)
		assert.are.same({}, more)
		shown, more = line_cargo.cargo_slots({ 0, 1, 2, 3, 4 }, 3)
		assert.are.same({ 0, 1 }, shown)
		assert.are.same({ 2, 3, 4 }, more)
		shown, more = line_cargo.cargo_slots({}, 3)
		assert.are.same({}, shown)
		assert.are.same({}, more)
	end)
end)
