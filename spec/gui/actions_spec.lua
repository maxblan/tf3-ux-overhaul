-- actions.lua: the line window's buttons and the uio.action event. The base react module is a
-- stand-in that records fired events (restored after loading, so other specs keep theirs).
---@class spec.actions.Fired
---@field name string
---@field param table

---@type spec.actions.Fired[]
local fired = {}

local saved_react = package.loaded["::/gui/main/react.lua"]
package.loaded["::/gui/main/react.lua"] = {
	---@param _src react.RefWrap?
	---@param name string
	---@param param table
	fireEvent = function(_src, name, param) fired[#fired + 1] = { name = name, param = param } end,
}
package.loaded["/ui_overhaul/gui/actions.lua"] = nil ---@type nil
local actions = require("/ui_overhaul/gui/actions.lua")
package.loaded["::/gui/main/react.lua"] = saved_react

local LINE = 100
local OLD, NEW = 1, 2

-- What the specs' stand-in for `api` provides: only what actions.lua reads.
---@class spec.actions.Api
---@field type { ComponentType: { TRANSPORT_VEHICLE: string }, enum: { TransportVehicleState: table<string, integer> } }
---@field engine spec.actions.Engine
---@field cmd spec.actions.Cmd

---@class spec.actions.Engine
---@field entityExists fun(e: integer): boolean
---@field getComponent fun(e: integer): spec.actions.Vehicle
---@field system { transportVehicleSystem: { getLineVehicles: fun(): integer[] } }

---@class spec.actions.Vehicle
---@field state integer
---@field transportVehicleConfig { vehicles: { purchaseTime: integer }[] }

---@class spec.actions.Cmd
---@field makeVehicleSendToDepotCmd fun(v: integer, sell: boolean): { vehicle: integer, sell: boolean }
---@field sendCommand fun(cmd: table, callback: fun(res: nil, success: boolean))

describe("actions", function()
	---@type { api: api, tr: fun(id: string): string, debug_print: fun(...: any) }
	local saved = {}
	---@type table[], string[], boolean
	local commands, log, send_ok
	local states ---@type table<integer, integer> vehicle -> TransportVehicleState
	local EN_ROUTE, GOING_TO_DEPOT, IN_DEPOT = 1, 2, 3

	before_each(function()
		saved.api, saved.tr, saved.debug_print = _G.api, _G._, _G.debugPrint
		fired, commands, log, send_ok = {}, {}, {}, true
		states = { [OLD] = EN_ROUTE, [NEW] = EN_ROUTE }
		local purchased = { [OLD] = 10, [NEW] = 20 }
		---@type spec.actions.Api
		local mock = {
			type = {
				ComponentType = { TRANSPORT_VEHICLE = "tv" },
				enum = { TransportVehicleState = { EN_ROUTE = EN_ROUTE, GOING_TO_DEPOT = GOING_TO_DEPOT,
					IN_DEPOT = IN_DEPOT } },
			},
			engine = {
				entityExists = function(e) return purchased[e] ~= nil end,
				getComponent = function(e)
					---@type spec.actions.Vehicle
					local tv = { state = states[e], transportVehicleConfig = { vehicles = { { purchaseTime = purchased[e] } } } }
					return tv
				end,
				system = { transportVehicleSystem = { getLineVehicles = function() return { NEW, OLD } end } },
			},
			cmd = {
				makeVehicleSendToDepotCmd = function(v, sell) return { vehicle = v, sell = sell } end,
				sendCommand = function(cmd, callback)
					commands[#commands + 1] = cmd
					callback(nil, send_ok)
				end,
			},
		}
		-- A partial stand-in (spec.actions.Api). The cast keeps LuaLS from merging the mock's types into
		-- the global `api` everywhere else; a plain assignment would.
		_G.api = mock --[[@as api]]
		---@param text string
		---@return string
		local function tr(text) return text end
		---@param ... any
		local function record(...) log[#log + 1] = table.concat({ ... }) end
		_G._, _G.debugPrint = tr, record
		actions.set_protected_entities(nil)
	end)

	after_each(function()
		_G.api, _G._, _G.debugPrint = saved.api, saved.tr, saved.debug_print
		actions.set_protected_entities(nil)
	end)

	---@return string[] messages
	---@return uo.actions.Feedback add_feedback
	local function collect()
		local messages = {} ---@type string[]
		return messages, function(message) messages[#messages + 1] = message end
	end

	it("clones the line's newest vehicle through the base handler, with the caller's feedback", function()
		local messages, add_feedback = collect()
		assert.is_true(actions.add_vehicle(LINE, add_feedback))
		assert.are.equal(1, #fired)
		assert.are.equal("duplicateVehicles", fired[1].name)
		assert.are.same({ NEW }, fired[1].param.vehicleEntities)
		assert.are.equal("function", type(fired[1].param.onBuy))
		-- the base handler reports a refusal (money, mission) through addFeedback
		fired[1].param.addFeedback("Could not clone vehicles (not enough money).", nil, nil, nil)
		assert.are.same({ "Could not clone vehicles (not enough money)." }, messages)
	end)

	it("sends the oldest vehicle to a depot to be sold", function()
		local messages, add_feedback = collect()
		assert.is_true(actions.remove_vehicle(LINE, add_feedback))
		assert.are.same({}, messages)
		assert.are.same({ { vehicle = OLD, sell = true } }, commands)
	end)

	it("skips vehicles already going to or in a depot, so a second click removes the next one", function()
		states[OLD] = GOING_TO_DEPOT
		assert.is_true(actions.remove_vehicle(LINE))
		assert.are.same({ { vehicle = NEW, sell = true } }, commands)
		states[NEW] = IN_DEPOT
		assert.is_false(actions.remove_vehicle(LINE))
		assert.is_false(actions.add_vehicle(LINE))
		assert.are.equal(1, #commands)
	end)

	it("reports a failed send to depot through the caller's feedback", function()
		send_ok = false
		local messages, add_feedback = collect()
		actions.remove_vehicle(LINE, add_feedback)
		assert.are.same({ "Vehicle could not be sent to depot." }, messages)
	end)

	it("keeps a vehicle the caller's gameCtx protects, and says why", function()
		local messages, add_feedback = collect()
		assert.is_false(actions.remove_vehicle(LINE, add_feedback, { [OLD] = true }))
		assert.are.same({}, commands)
		assert.are.same({ "Vehicle cannot be sold at this time." }, messages)
	end)

	it("keeps protected vehicles on the uio.action event, from the mission's setProtectedEntities", function()
		actions.set_protected_entities({ [OLD] = { someConfig = true } })
		actions.run({ name = "remove_vehicle", entity = LINE })
		actions.run({ name = "retire_vehicle", entity = OLD })
		assert.are.same({}, commands)
		local refused = 0
		for _i, line in ipairs(log) do
			if line:find("Vehicle cannot be sold at this time.", 1, true) then refused = refused + 1 end
		end
		assert.are.equal(2, refused)
	end)

	it("removes again once the mission lifts the protection", function()
		actions.set_protected_entities({ [OLD] = true })
		actions.set_protected_entities({})
		actions.run({ name = "remove_vehicle", entity = LINE })
		assert.are.same({ { vehicle = OLD, sell = true } }, commands)
	end)

	it("tells the line window when Remove Vehicle would be refused, so its button stays silent", function()
		assert.is_false(actions.remove_refused(LINE, {}))
		assert.is_false(actions.remove_refused(LINE, { [NEW] = true }))
		assert.is_false(actions.remove_refused(LINE, { [OLD] = false }))
		assert.is_true(actions.remove_refused(LINE, { [OLD] = { someConfig = true } }))
		actions.set_protected_entities({ [OLD] = true })
		assert.is_true(actions.remove_refused(LINE))
		assert.are.same({}, commands)
	end)

	it("logs unknown action names", function()
		actions.run({ name = "save_game" })
		assert.are.same({}, commands)
		assert.are.same({}, fired)
		assert.is_truthy(log[1]:find("unknown action save_game", 1, true))
	end)
end)
