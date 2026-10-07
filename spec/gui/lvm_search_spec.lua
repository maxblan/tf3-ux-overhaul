-- lvm_search.lua: the Line Manager's vehicle list (its state ref) as the search narrows and restores it,
-- while the base changes the selection, replaces the list or takes vehicles off through its api. The
-- engine is a stand-in with five vehicles; the base modules are stand-ins (fake_react.load).
local fake_react = require("fake_react")

local NAMES = { [1] = "Zug 1", [2] = "Bus 2", [3] = "Zug 3", [4] = "Tram 4", [5] = "Zug 5" }
local LINE_OF = { [1] = 11, [2] = 12, [3] = 11, [4] = 13, [5] = 14 }
local LINE_NAMES = { [11] = "Nord", [12] = "Stadt", [13] = "Ring", [14] = "Hafen" }
local MODEL_OF = { [1] = 101, [2] = 102, [3] = 101, [4] = 103, [5] = 101 }
local MODEL_NAMES = { [101] = "Re 450", [102] = "Citaro", [103] = "Combino" }

---A stand-in for the Line Manager's vehicleManagerStateRef.
---@class spec.lvm_search.Ref
---@field value game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState
local Ref = {}
Ref.__index = Ref
---@return game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState
function Ref:get() return self.value end
---@param value game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState
function Ref:set(value) self.value = value end

---@param selected integer[]
---@param unselected integer[]
---@return game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState
local function state(selected, unselected)
	local result = { vehicleListEntitiesSelected = {}, vehicleListEntitiesUnselected = {}, carriers = {} }
	for _i, v in ipairs(selected) do table.insert(result.vehicleListEntitiesSelected, { entity = v }) end
	for _i, v in ipairs(unselected) do table.insert(result.vehicleListEntitiesUnselected, { entity = v }) end
	return result --[[@as game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState]]
end

---@param ref spec.lvm_search.Ref
---@return integer[] selected
---@return integer[] unselected
local function listed(ref)
	local s, u = {}, {} ---@type integer[], integer[]
	for _i, ear in ipairs(ref.value.vehicleListEntitiesSelected) do s[#s + 1] = ear.entity end
	for _i, ear in ipairs(ref.value.vehicleListEntitiesUnselected) do u[#u + 1] = ear.entity end
	table.sort(s)
	table.sort(u)
	return s, u
end

---@return uo.gui.lvm_search
local function load()
	return fake_react.load("/ui_overhaul/gui/lvm_search.lua", {
		["::/scripts/lang_util.tl"] = {
			---@param text string
			---@param part string
			---@return boolean
			stringContains = function(text, part) return text:lower():find(part:lower(), 1, true) ~= nil end,
		},
		["::/scripts/entity_util.tl"] = {
			entityChanged0 = function() return false end,
			isOwnedByPlayer = function() return true end,
			---@param e integer
			---@return { entity: integer }
			makeEntityAndRevision = function(e) return { entity = e } end,
		},
	}) --[[@as uo.gui.lvm_search]]
end

describe("lvm_search", function()
	local globals = _G ---@type table<string, any> global name -> value, of any type
	local saved = {} ---@type table<string, any> global name -> its value before the spec
	local ref ---@type spec.lvm_search.Ref
	local params ---@type game.gui.line_vehicle_mgmt.vehicle_list_react_util.VehicleListParams
	local search ---@type uo.gui.lvm_search
	before_each(function()
		for _i, name in ipairs({ "api", "_", "debugPrint" }) do saved[name] = globals[name] end
		globals.debugPrint = function() end
		---@param text string
		---@return string
		globals._ = function(text) return text end
		local mock = {
			type = { ComponentType = { TRANSPORT_VEHICLE = "TV" } },
			engine = {
				entityExists = function() return true end,
				---@param e integer
				---@return table?
				getComponent = function(e)
					if not NAMES[e] then return nil end
					return { line = LINE_OF[e], carrier = 1,
						transportVehicleConfig = { vehicles = { { part = { modelId = MODEL_OF[e] } } } } }
				end,
				util = {
					---@param e integer
					---@return string
					getEntityName = function(e) return NAMES[e] or LINE_NAMES[e] end,
				},
			},
			res = { modelRep = {
				---@param id integer
				---@return table
				get = function(id) return { metadata = { description = { name = MODEL_NAMES[id] } } } end,
			} },
		}
		-- A partial stand-in; the cast keeps LuaLS from merging the mock's types into the global `api`.
		_G.api = mock --[[@as api]]
		ref = setmetatable({ value = state({ 1 }, { 2, 3 }) }, Ref)
		params = { commonParams = { vehicleManagerStateRef = ref }, vehicles = { 1, 2, 3 } } --[[@as any]]
		search = load()
	end)
	after_each(function()
		for name, value in pairs(saved) do globals[name] = value end
	end)

	---@param text string
	local function type_text(text)
		search.set_text(text)
		search.step(params)
	end

	it("shows the vehicles whose name, model or line matches; the rest leave the list", function()
		type_text("zug")
		local s, u = listed(ref)
		assert.are.same({ 1 }, s)
		assert.are.same({ 3 }, u)
		type_text("citaro") -- the model's name
		s, u = listed(ref)
		assert.are.same({}, s)
		assert.are.same({ 2 }, u)
		type_text("NORD") -- the line's name, in any case
		s, u = listed(ref)
		assert.are.same({}, s)
		assert.are.same({ 1, 3 }, u)
	end)

	it("puts the hidden vehicles back, unselected, when the search is cleared", function()
		type_text("bus")
		type_text("")
		local s, u = listed(ref)
		assert.are.same({}, s)
		assert.are.same({ 1, 2, 3 }, u)
	end)

	it("keeps the hidden vehicles when the selection changes (the list's select all)", function()
		type_text("zug")
		ref:set(state({ 1, 3 }, {}))
		search.step(params)
		type_text("")
		local s, u = listed(ref)
		assert.are.same({ 1, 3 }, s)
		assert.are.same({ 2 }, u)
	end)

	it("forgets the hidden vehicles when another line's vehicles replace the list", function()
		type_text("zug")
		ref:set(state({ 5 }, { 4 }))
		search.step(params)
		local s, u = listed(ref)
		assert.are.same({ 5 }, s)
		assert.are.same({}, u)
		type_text("")
		s, u = listed(ref)
		assert.are.same({ 5 }, s)
		assert.are.same({ 4 }, u)
	end)

	it("follows the manager's api: what it takes off the list stays off, what it adds is matched", function()
		local api_table = {
			---@param entities integer[]
			removeVehiclesFromVehicleList = function(entities)
				local gone = {} ---@type table<integer, true>
				for _i, e in ipairs(entities) do gone[e] = true end
				local s, u = listed(ref)
				local keep_s, keep_u = {}, {} ---@type integer[], integer[]
				for _i, e in ipairs(s) do if not gone[e] then keep_s[#keep_s + 1] = e end end
				for _i, e in ipairs(u) do if not gone[e] then keep_u[#keep_u + 1] = e end end
				ref:set(state(keep_s, keep_u))
			end,
			---@param entities integer[]
			addVehiclesToVehicleListAndSelect = function(entities)
				local s, u = listed(ref)
				for _i, e in ipairs(entities) do s[#s + 1] = e end
				ref:set(state(s, u))
			end,
			clearVehicleList = function() ref:set(state({}, {})) end,
		}
		params.managerRef = { get = function() return { getApi = function() return api_table end } end } --[[@as any]]
		search.wrap_api(params)
		type_text("zug") -- Bus 2 hidden
		api_table.removeVehiclesFromVehicleList({ 1, 2 }) -- the line of 1 and 2 deselected
		search.step(params)
		api_table.addVehiclesToVehicleListAndSelect({ 4, 5 }) -- another line selected: Tram 4 does not match
		search.step(params)
		local s, u = listed(ref)
		assert.are.same({ 5 }, s)
		assert.are.same({ 3 }, u)
		type_text("")
		s, u = listed(ref)
		assert.are.same({ 5 }, s)
		assert.are.same({ 3, 4 }, u) -- 4 back, 2 stays off
		type_text("zug")
		api_table.clearVehicleList()
		search.step(params)
		type_text("")
		s, u = listed(ref)
		assert.are.same({}, s)
		assert.are.same({}, u)
	end)

	it("keeps the list but shows and selects nothing when nothing matches", function()
		type_text("xyz")
		local s, u = listed(ref)
		assert.are.same({}, s)
		assert.are.same({ 1, 2, 3 }, u)
		assert.are.same({}, search.shown({ 1, 2, 3 }))
		ref:set(state({ 1, 2, 3 }, {})) -- the list's select all
		search.step(params)
		s, u = listed(ref)
		assert.are.same({}, s)
		assert.are.same({ 1, 2, 3 }, u)
		type_text("")
		assert.are.same({ 1, 2, 3 }, search.shown({ 1, 2, 3 }))
	end)

	it("ends with the Line Manager; its list gets the hidden vehicles back the next time it shows", function()
		type_text("zug")
		search.unmount()
		assert.are.equal("", search.text())
		search.step(params)
		local _s, u = listed(ref)
		assert.are.same({ 2, 3 }, u)
	end)
end)
