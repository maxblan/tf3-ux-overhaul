-- actions.lua: the line window's buttons and the uio.action event. The base react module is a
-- stand-in that records fired events (restored after loading, so other specs keep theirs).
local fired = {}

local saved_react = package.loaded["::/gui/main/react.lua"]
package.loaded["::/gui/main/react.lua"] = {
	fireEvent = function(_src, name, param) fired[#fired + 1] = { name = name, param = param } end,
}
package.loaded["/ui_overhaul/gui/actions.lua"] = nil
local actions = require("/ui_overhaul/gui/actions.lua")
package.loaded["::/gui/main/react.lua"] = saved_react

local LINE = 100
local OLD, NEW = 1, 2

describe("actions", function()
	local saved = {}
	local commands, log, send_ok

	before_each(function()
		saved.api, saved.tr, saved.debug_print = _G.api, _G._, _G.debugPrint
		fired, commands, log, send_ok = {}, {}, {}, true
		local purchased = { [OLD] = 10, [NEW] = 20 }
		_G.api = {
			type = { ComponentType = { TRANSPORT_VEHICLE = "tv" } },
			engine = {
				entityExists = function(e) return purchased[e] ~= nil end,
				getComponent = function(e)
					return { transportVehicleConfig = { vehicles = { { purchaseTime = purchased[e] } } } }
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
		_G._ = function(text) return text end
		_G.debugPrint = function(...) log[#log + 1] = table.concat({ ... }) end
		actions.set_protected_entities(nil)
	end)

	after_each(function()
		_G.api, _G._, _G.debugPrint = saved.api, saved.tr, saved.debug_print
		actions.set_protected_entities(nil)
	end)

	local function collect()
		local messages = {}
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
