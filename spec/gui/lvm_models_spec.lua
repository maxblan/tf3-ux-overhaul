-- Line Manager model row: grouping, the cached view and the selection it writes.

local EN_ROUTE, IN_DEPOT = 1, 0
local world, calls

-- Stand-ins for the base modules lvm_models.lua loads.
package.loaded["::/gui/main/react.lua"] = {
	RegisterRecipe = function(name, fn) return function(p) return { recipe = name, params = p, fn = fn } end end,
}
package.loaded["::/gui/main/builtin.lua"] = setmetatable({
	type = { Orientation = {}, ScrollBarPolicy = {} },
}, { __index = function(_t, kind) return function(p) return { kind = kind, params = p } end end })
package.loaded["::/scripts/lang_util.tl"] = {
	format = function(text, values) return (text:gsub("{(%w+)}", function(k) return tostring(values[k]) end)) end,
	formatInt = tostring,
}
package.loaded["::/scripts/entity_util.tl"] = {
	makeEntityAndRevision = function(v)
		if not world.vehicles[v] then return nil end
		return { entity = v, revision = { num = { world.vehicles[v].rev, 0, 0 } } }
	end,
	entityChanged0 = function(ear)
		local v = world.vehicles[ear.entity]
		return not v or ear.revision.num[1] < v.rev
	end,
	isOwnedByPlayer = function(e) return world.vehicles[e] ~= nil and not world.vehicles[e].foreign end,
}
package.loaded["::/gui/line_vehicle_mgmt/vehicle_react_util.tl"] = {
	VehicleWidget = function(p) return { widget = p } end,
}
_G._ = function(text) return text end
_G.debugPrint = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	world.log[#world.log + 1] = table.concat(parts)
end

local NAMES = { [1] = "Isuzu", [2] = "Volvo", [3] = "Loco", [4] = "Coach" }

--- vehicles: id -> { ids = {model ids}, line = line or nil }
local function install(vehicles, lines)
	world = { vehicles = {}, lines = lines or {}, log = {}, shift = false }
	calls = { components = 0, closed = 0 }
	for id, v in pairs(vehicles) do
		world.vehicles[id] = { ids = v.ids, line = v.line, rev = 1, carrier = v.carrier or 0, foreign = v.foreign,
			state = v.line and EN_ROUTE or IN_DEPOT }
	end
	_G.api = {
		type = {
			ComponentType = { TRANSPORT_VEHICLE = "tv" },
			enum = { TransportVehicleState = { EN_ROUTE = EN_ROUTE, AT_TERMINAL = 2, IN_DEPOT = IN_DEPOT } },
		},
		engine = {
			entityExists = function(e) return world.vehicles[e] ~= nil end,
			getComponent = function(e, kind)
				assert(kind == "tv")
				calls.components = calls.components + 1
				local v = world.vehicles[e]
				if not v then return nil end
				local parts = {}
				for i, id in ipairs(v.ids) do parts[i] = { part = { modelId = id } } end
				return { transportVehicleConfig = { vehicles = parts }, line = v.line or -1, state = v.state,
					carrier = v.carrier }
			end,
			util = { getPlayer = function() return 7 end },
			system = {
				lineSystem = { getLinesForPlayer = function()
					local result = {}
					for line in pairs(world.lines) do result[#result + 1] = line end
					table.sort(result)
					return result
				end },
				transportVehicleSystem = { getLineVehicles = function(line) return world.lines[line] or {} end },
			},
		},
		res = { modelRep = { get = function(id) return { metadata = { description = { name = NAMES[id] } } } end } },
		gui = { inputAction = { modifierOnlyActionIsActive = function(ia)
			return ia == "IA_PRECISION_MODE" and world.shift
		end } },
	}
end

local function ref(value)
	return { value = value, get = function(self) return self.value end, set = function(self, v) self.value = v end }
end

local function ear(v) return { entity = v, revision = { num = { 1, 0, 0 } } } end

--- VehicleList parameters for a list with `selected` and `unselected` vehicles.
local function list(selected, unselected)
	local s, u, vehicles = {}, {}, {}
	for _i, v in ipairs(selected) do s[#s + 1] = ear(v); vehicles[#vehicles + 1] = v end
	for _i, v in ipairs(unselected) do u[#u + 1] = ear(v); vehicles[#vehicles + 1] = v end
	local vm_api = { closeVehicleStore = function() calls.closed = calls.closed + 1 end }
	local manager = { getApi = function() return vm_api end }
	return {
		vehicles = vehicles,
		managerRef = ref(manager),
		commonParams = { vehicleManagerStateRef = ref({ vehicleListEntitiesSelected = s, vehicleListEntitiesUnselected = u,
			carriers = {} }) },
	}
end

local function entities(entries)
	local result = {}
	for i, e in ipairs(entries) do result[i] = e.entity end
	table.sort(result)
	return result
end

local lvm_models

-- Line 100: three Isuzu buses and one Volvo; line 200: two Isuzu and a Volvo; 300: a train.
local FLEET = {
	[11] = { ids = { 1 }, line = 100 }, [12] = { ids = { 1 }, line = 100 }, [13] = { ids = { 1 }, line = 100 },
	[14] = { ids = { 2 }, line = 100 },
	[21] = { ids = { 1 }, line = 200 }, [22] = { ids = { 1 }, line = 200 }, [23] = { ids = { 2 }, line = 200 },
	[31] = { ids = { 3, 4, 4 }, line = 300 }, [32] = { ids = { 4, 3, 4 }, line = 300 },
}
local LINES = { [100] = { 11, 12, 13, 14 }, [200] = { 21, 22, 23 }, [300] = { 31, 32 } }

describe("lvm_models", function()
	before_each(function()
		install(FLEET, LINES)
		package.loaded["/ui_overhaul/gui/lvm_models.lua"] = nil
		lvm_models = require("/ui_overhaul/gui/lvm_models.lua")
	end)

	it("keys a model by its id, a train by its composition in any order", function()
		assert.are.equal("7", lvm_models.model_key({ 7 }))
		assert.are.equal("3x1,4x2", lvm_models.model_key({ 3, 4, 4 }))
		assert.are.equal(lvm_models.model_key({ 4, 3, 4 }), lvm_models.model_key({ 3, 4, 4 }))
		assert.truthy(lvm_models.model_key({ 3, 4 }) ~= lvm_models.model_key({ 3, 4, 4 }))
	end)

	it("names a train like the vehicle window", function()
		local name_of = function(id) return NAMES[id] end
		assert.are.equal("Isuzu", lvm_models.model_name({ 1 }, name_of))
		assert.are.equal("Loco\n + Coach (2x)", lvm_models.model_name({ 3, 4, 4 }, name_of))
	end)

	it("groups the list by model, most vehicles first", function()
		local groups, by_entity = lvm_models.group({ 14, 11, 31, 12, 32, 13 }, lvm_models.read_ids, lvm_models.name_of)
		assert.are.same({ "1", "3x1,4x2", "2" }, { groups[1].key, groups[2].key, groups[3].key })
		assert.are.same({ 3, 2, 1 }, { groups[1].count, groups[2].count, groups[3].count })
		assert.are.equal("Isuzu", groups[1].name)
		assert.are.equal("3x1,4x2", by_entity[32])
	end)

	it("counts the vehicles of each listed model on other lines and caches the view by list members", function()
		local view = lvm_models.view({ 11, 12, 13, 14 })
		assert.are.equal(2, view.by_key["1"].more) -- 21, 22
		assert.are.equal(1, view.by_key["2"].more) -- 23
		local reads = calls.components
		assert.are.equal(view, lvm_models.view({ 14, 13, 12, 11 })) -- same members, other order: no engine reads
		assert.are.equal(reads, calls.components)
		assert.truthy(view ~= lvm_models.view({ 11, 12, 13 }))
	end)

	it("shows the row for two models, or for one model other lines use too", function()
		assert.is_true(lvm_models.row_visible(lvm_models.view({ 11, 14 }).groups))
		assert.is_true(lvm_models.row_visible(lvm_models.view({ 11, 12 }).groups))
		assert.is_false(lvm_models.row_visible(lvm_models.view({ 31, 32 }).groups))
		assert.is_nil(lvm_models.update(list({ 31, 32 }, {})))
		assert.are.equal("UioLvmModels", lvm_models.update(list({ 11 }, { 14 })).recipe)
	end)

	it("targets the selection's single model, else the list's only model", function()
		local view = lvm_models.view({ 11, 12, 14 })
		local function target(selected)
			local group = lvm_models.target(view.groups, view.by_entity, view.by_key, selected)
			return group and group.key
		end
		assert.are.equal("1", target({ 11, 12 }))
		assert.is_nil(target({ 11, 14 }))
		assert.is_nil(target({}))
		assert.are.equal("1", lvm_models.exact_key(view.by_entity, view.by_key, { 12, 11 }))
		assert.is_nil(lvm_models.exact_key(view.by_entity, view.by_key, { 11 }))
		view = lvm_models.view({ 11, 12 })
		assert.are.equal("1", target({}))
	end)

	it("selects exactly the listed vehicles of a model, after closing the vehicle store", function()
		local params = list({ 11, 12, 13, 14 }, { 21 })
		params.commonParams.vehicleManagerStateRef.set = function(self, value)
			assert.are.equal(1, calls.closed) -- an open Replace window would keep the old selection
			self.value = value
		end
		lvm_models.update(params)
		assert.are.equal(1, lvm_models.select_model("2"))
		local state = params.commonParams.vehicleManagerStateRef:get()
		assert.are.same({ 14 }, entities(state.vehicleListEntitiesSelected))
		assert.are.same({ 11, 12, 13, 21 }, entities(state.vehicleListEntitiesUnselected))
		assert.are.same({ 0 }, state.carriers)
	end)

	it("drops changed and foreign vehicles like makeVehicleManagerState", function()
		world.vehicles[12].rev = 2
		world.vehicles[13].foreign = true
		local state = lvm_models.make_state({ ear(11), ear(12) }, { ear(13), ear(99) })
		assert.are.same({ 11 }, entities(state.vehicleListEntitiesSelected))
		assert.are.same({}, entities(state.vehicleListEntitiesUnselected))
	end)

	it("adds a model's vehicles from all lines, selected, and unselects the rest", function()
		local params = list({ 11, 14 }, {})
		lvm_models.update(params)
		assert.are.equal(5, lvm_models.pull_model("1"))
		local state = params.commonParams.vehicleManagerStateRef:get()
		assert.are.same({ 11, 12, 13, 21, 22 }, entities(state.vehicleListEntitiesSelected))
		assert.are.same({ 14 }, entities(state.vehicleListEntitiesUnselected))
	end)

	it("Shift+click selects the vehicle's model in the list", function()
		local params = list({ 11, 12, 13, 14 }, {})
		lvm_models.update(params)
		assert.is_false(lvm_models.shift_held())
		world.shift = true
		assert.is_true(lvm_models.shift_held())
		assert.is_true(lvm_models.select_same_model(12))
		local state = params.commonParams.vehicleManagerStateRef:get()
		assert.are.same({ 11, 12, 13 }, entities(state.vehicleListEntitiesSelected))
		assert.is_false(lvm_models.select_same_model(99))
	end)

	it("counts the lines of vehicles on lines", function()
		assert.are.equal(1, lvm_models.line_count({ 11, 12 }))
		assert.are.equal(2, lvm_models.line_count({ 11, 21, 31 }, 2))
		world.vehicles[21].state = IN_DEPOT
		assert.are.equal(1, lvm_models.line_count({ 11, 21 }))
	end)

	it("renders one button per model and the 'In all lines' button for the selected model", function()
		local row = lvm_models.update(list({ 11, 12 }, { 14 }))
		local node = row.fn(row.params)
		local inner = node.params.children[1].params.layout.params.children
		local chips = inner[1].params.content.params.layout.params.children
		assert.are.equal(2, #chips)
		assert.are.equal("vehicle-button, selected", chips[1].params.meta.class)
		local pull = inner[2].params
		assert.is_true(pull.meta.enabled)
		assert.are.equal("Select all 5 Isuzu from all lines", pull.meta.tooltip)
	end)

	it("logs the testbench selection against the expected count", function()
		lvm_models.update(list({ 11, 12, 13, 14 }, {}))
		lvm_models.debug({ action = "pull", index = 1 })
		assert.truthy(world.log[#world.log]:find("selected=5 expected=5", 1, true))
		assert.truthy(world.log[#world.log]:find("ok", 1, true))
	end)
end)
