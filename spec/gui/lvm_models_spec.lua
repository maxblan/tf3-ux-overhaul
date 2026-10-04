-- Line Manager model row: grouping, the cached view and the selection it writes.

---@class spec.lvm_models.Vehicle a vehicle of the stand-in engine
---@field ids integer[] model ids of its parts
---@field line? integer
---@field rev integer revision number
---@field carrier integer
---@field foreign? boolean
---@field state integer

---@class spec.lvm_models.World
---@field vehicles table<integer, spec.lvm_models.Vehicle>
---@field lines table<integer, integer[]> line -> its vehicles
---@field log string[]
---@field shift boolean whether Shift is held

---@class spec.lvm_models.Timer the row's useStepStateTimer
---@field fn fun(old?: integer): integer
---@field interval number
---@field value integer

---@class spec.lvm_models.Ear the stand-in entity_util's entity and revision
---@field entity integer
---@field revision { num: integer[] }

local EN_ROUTE, IN_DEPOT = 1, 0
local world ---@type spec.lvm_models.World
local calls ---@type { components: integer, closed: integer }
local timer ---@type spec.lvm_models.Timer?

-- Stand-ins for the base modules lvm_models.lua loads.
package.loaded["::/gui/main/react.lua"] = {
	RegisterRecipe = function(name, fn) return function(p) return { recipe = name, params = p, fn = fn } end end,
}
package.loaded["::/gui/main/builtin.lua"] = setmetatable({
	type = { Orientation = {}, ScrollBarPolicy = {} },
}, { __index = function(_t, kind) return function(p) return { kind = kind, params = p } end end })
package.loaded["::/gui/main/engine_react_util.tl"] = {
	---@param fn fun(old?: integer): integer
	---@param interval number
	---@return { old: fun(): integer }
	useStepStateTimer = function(fn, interval)
		local t = timer or { fn = fn, interval = interval, value = fn(nil) }
		timer = t
		t.fn = fn
		return { old = function() return t.value end }
	end,
}
---@param a table<any, any>|string|number|boolean|nil a fleet or a part of one
---@param b table<any, any>|string|number|boolean|nil
---@return boolean
local function deep_equals(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do if not deep_equals(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
package.loaded["::/scripts/table_util.tl"] = { deepEquals = deep_equals }
package.loaded["::/scripts/lang_util.tl"] = {
	---@param text string
	---@param values table<string, string|number>
	---@return string
	format = function(text, values) return (text:gsub("{(%w+)}", function(k) return tostring(values[k]) end)) end,
	formatInt = tostring,
}
package.loaded["::/scripts/entity_util.tl"] = {
	---@param v integer
	---@return spec.lvm_models.Ear?
	makeEntityAndRevision = function(v)
		if not world.vehicles[v] then return nil end
		return { entity = v, revision = { num = { world.vehicles[v].rev, 0, 0 } } }
	end,
	---@param ear spec.lvm_models.Ear
	---@return boolean
	entityChanged0 = function(ear)
		local v = world.vehicles[ear.entity]
		return not v or ear.revision.num[1] < v.rev
	end,
	---@param e integer
	---@return boolean
	isOwnedByPlayer = function(e) return world.vehicles[e] ~= nil and not world.vehicles[e].foreign end,
}
package.loaded["::/gui/line_vehicle_mgmt/vehicle_react_util.tl"] = {
	---@param p game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleWidgetParams
	---@return { widget: game.gui.line_vehicle_mgmt.vehicle_react_util.VehicleWidgetParams }
	VehicleWidget = function(p) return { widget = p } end,
}
---@param text string
---@return string
local function tr(text) return text end
---@param ... any
local function record(...)
	local parts = {} ---@type string[]
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	world.log[#world.log + 1] = table.concat(parts)
end
_G._, _G.debugPrint = tr, record

-- What the specs' stand-in for `api` provides: only what lvm_models.lua reads.
---@class spec.lvm_models.Api
---@field type { ComponentType: { TRANSPORT_VEHICLE: string }, enum: { TransportVehicleState: table<string, integer> } }
---@field engine spec.lvm_models.Engine
---@field res { modelRep: { get: fun(id: integer): { metadata: { description: { name: string? } } } } }
---@field gui { inputAction: { modifierOnlyActionIsActive: fun(ia: string): boolean } }

---@class spec.lvm_models.Engine
---@field entityExists fun(e: integer): boolean
---@field getComponent fun(e: integer, kind: string): table?
---@field util { getPlayer: fun(): integer }
---@field system spec.lvm_models.System

---@class spec.lvm_models.System
---@field lineSystem { getLinesForPlayer: fun(): integer[] }
---@field transportVehicleSystem { getLineVehicles: fun(line: integer): integer[] }

local NAMES = { [1] = "Isuzu", [2] = "Volvo", [3] = "Loco", [4] = "Coach" }

--- vehicles: id -> { ids = {model ids}, line = line or nil }
---@param vehicles table<integer, { ids: integer[], line?: integer, carrier?: integer, foreign?: boolean }>
---@param lines? table<integer, integer[]>
local function install(vehicles, lines)
	world = { vehicles = {}, lines = lines or {}, log = {}, shift = false }
	calls = { components = 0, closed = 0 }
	for id, v in pairs(vehicles) do
		world.vehicles[id] = { ids = v.ids, line = v.line, rev = 1, carrier = v.carrier or 0, foreign = v.foreign,
			state = v.line and EN_ROUTE or IN_DEPOT }
	end
	---@type spec.lvm_models.Api
	local mock = {
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
				local parts = {} ---@type { part: { modelId: integer } }[]
				for i, id in ipairs(v.ids) do parts[i] = { part = { modelId = id } } end
				return { transportVehicleConfig = { vehicles = parts }, line = v.line or -1, state = v.state,
					carrier = v.carrier }
			end,
			util = { getPlayer = function() return 7 end },
			system = {
				lineSystem = { getLinesForPlayer = function()
					local result = {} ---@type integer[]
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
	-- A partial stand-in (spec.lvm_models.Api). The cast keeps LuaLS from merging the mock's types into
	-- the global `api` everywhere else; a plain assignment would.
	_G.api = mock --[[@as api]]
end

---@class spec.lvm_models.Ref<T> a stand-in ref
---@field value T
---@field get fun(self: spec.lvm_models.Ref<T>): T
---@field set fun(self: spec.lvm_models.Ref<T>, v: T)

---@generic T
---@param value T
---@return spec.lvm_models.Ref<T>
local function ref(value)
	return { value = value, get = function(self) return self.value end, set = function(self, v) self.value = v end }
end

---@param v integer
---@return game.scripts.entity_util.EntityAndRevision
local function ear(v) return { entity = v, revision = { num = { 1, 0, 0 } } } end

--- One step of the row's timer, as useStepStateTimer runs it.
---@return integer
local function tick()
	local t = assert(timer, "the row is not mounted")
	t.value = t.fn(t.value)
	return t.value
end

--- Replaces vehicle `v` in place (makeVehicleReplaceCmd keeps the id) with model ids `ids`.
---@param v integer
---@param ids integer[]
local function replace(v, ids) world.vehicles[v].ids = ids end

--- A node as the stand-in react and builtin modules above build it: plain tables of several shapes
--- (recipe calls { recipe, params, fn }, builtins { kind, params }, widgets { widget }) where the game
--- builds opaque nodes, so the specs read them untyped.
---@param node_id react.TreeNodeId
---@return any node
local function stand_in(node_id) return node_id end

--- Renders the row node that update() returned; returns the layout and the chips' buttons.
---@param node_id react.TreeNodeId
---@return any node the rendered layout (see stand_in)
---@return any chips the model buttons, nil while the row is hidden
---@return any pull the "In all lines" button's params
local function render(node_id)
	local row = stand_in(node_id)
	local node = row.fn(row.params) ---@type any see stand_in
	local inner = node.params.children and node.params.children[1].params.layout.params.children ---@type any
	return node, inner and inner[1].params.content.params.layout.params.children, inner and inner[2].params
end

--- VehicleList parameters for a list with `selected` and `unselected` vehicles.
---@param selected integer[]
---@param unselected integer[]
---@return uo.gui.lvm_models.ListParams
local function list(selected, unselected)
	---@type game.scripts.entity_util.EntityAndRevision[], game.scripts.entity_util.EntityAndRevision[], integer[]
	local s, u, vehicles = {}, {}, {}
	for _i, v in ipairs(selected) do s[#s + 1] = ear(v); vehicles[#vehicles + 1] = v end
	for _i, v in ipairs(unselected) do u[#u + 1] = ear(v); vehicles[#vehicles + 1] = v end
	local vm_api = { closeVehicleStore = function() calls.closed = calls.closed + 1 end }
	local manager = { getApi = function() return vm_api end }
	local params = {
		vehicles = vehicles,
		managerRef = ref(manager),
		commonParams = { vehicleManagerStateRef = ref({ vehicleListEntitiesSelected = s, vehicleListEntitiesUnselected = u,
			carriers = {} }) },
	}
	-- partial: the vehicles, the manager's closeVehicleStore and the state ref are what lvm_models uses
	return params --[[@as uo.gui.lvm_models.ListParams]]
end

---@param entries game.scripts.entity_util.EntityAndRevision[]
---@return integer[]
local function entities(entries)
	local result = {} ---@type integer[]
	for i, e in ipairs(entries) do result[i] = e.entity end
	table.sort(result)
	return result
end

local lvm_models ---@type uo.gui.lvm_models

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
		timer = nil
		package.loaded["/ui_overhaul/gui/lvm_models.lua"] = nil ---@type nil
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

	it("reads the fleet again after a failed read of the same list", function()
		local engine = _G.api.engine --[[@as spec.lvm_models.Engine]] -- the stand-in installed above
		local get = engine.getComponent
		engine.getComponent = function() error("engine read failed") end
		assert.is_false((pcall(lvm_models.view, { 11, 12, 13, 14 })))
		engine.getComponent = get
		local view = lvm_models.view({ 11, 12, 13, 14 })
		assert.are.equal(2, view.by_key["1"].more)
	end)

	it("shows the row for two models, or for one model other lines use too", function()
		assert.is_true(lvm_models.row_visible(lvm_models.view({ 11, 14 }).groups))
		assert.is_true(lvm_models.row_visible(lvm_models.view({ 11, 12 }).groups))
		assert.is_false(lvm_models.row_visible(lvm_models.view({ 31, 32 }).groups))
		local row = lvm_models.update(list({ 31, 32 }, {}))
		assert.are.equal("UioLvmModels", stand_in(row).recipe) -- stays mounted, so its refresh can show it later
		local node, chips = render(row)
		assert.are.equal("BoxLayout", node.kind)
		assert.is_nil(chips)
		assert.are.equal(2, #select(2, render(lvm_models.update(list({ 11 }, { 14 })))))
	end)

	it("re-reads the models after a Replace that keeps the vehicle ids", function()
		local row = lvm_models.update(list({ 11, 12, 13, 14 }, {}))
		lvm_models.view({ 11, 12, 13, 14 })
		local reads = calls.components
		render(row)
		assert.are.equal(reads, calls.components) -- mounting the timer reads nothing
		assert.are.equal(3, lvm_models.view({ 11, 12, 13, 14 }).by_key["1"].count)
		local view, stamp = lvm_models.view({ 11, 12, 13, 14 }), tick()
		assert.are.equal(view, lvm_models.view({ 11, 12, 13, 14 })) -- nothing changed: same view
		assert.are.equal(stamp, tick())

		replace(12, { 2 })
		replace(13, { 2 })
		assert.truthy(tick() ~= stamp)
		view = lvm_models.view({ 11, 12, 13, 14 })
		assert.are.equal(1, view.by_key["1"].count)
		assert.are.equal(3, view.by_key["2"].count)
		assert.are.equal("2", view.by_entity[12])
		local _node, chips, pull = render(row)
		assert.are.equal(2, #chips)
		assert.are.same({ 12, 13, 14 }, chips[1].params.content.widget.vehicleEntities)
		assert.are.equal("Select vehicles of one model first", pull.meta.tooltip)
	end)

	it("selects by the models the vehicles have now, before the row refreshed", function()
		local params = list({ 11, 12, 13, 14 }, {})
		lvm_models.update(params)
		assert.are.equal(3, lvm_models.view({ 11, 12, 13, 14 }).by_key["1"].count)
		replace(12, { 2 })
		assert.are.equal(2, lvm_models.select_model("1"))
		local state = params.commonParams.vehicleManagerStateRef:get()
		assert.are.same({ 11, 13 }, entities(state.vehicleListEntitiesSelected))

		replace(13, { 2 })
		world.shift = true
		assert.is_true(lvm_models.select_same_model(13))
		state = params.commonParams.vehicleManagerStateRef:get()
		assert.are.same({ 12, 13, 14 }, entities(state.vehicleListEntitiesSelected))

		assert.are.equal(4, lvm_models.pull_model("2")) -- 12, 13, 14 and line 200's 23
		state = params.commonParams.vehicleManagerStateRef:get()
		assert.are.same({ 12, 13, 14, 23 }, entities(state.vehicleListEntitiesSelected))
	end)

	it("follows the other lines' fleets", function()
		local row = lvm_models.update(list({ 14 }, {}))
		local pull = select(3, render(row))
		assert.are.equal("Select all 2 Volvo from all lines", pull.meta.tooltip) -- 14 and 23

		world.vehicles[24] = { ids = { 2 }, line = 200, rev = 1, carrier = 0, state = EN_ROUTE }
		world.lines[200] = { 21, 22, 23, 24 }
		tick()
		pull = select(3, render(row))
		assert.are.equal("Select all 3 Volvo from all lines", pull.meta.tooltip)

		replace(23, { 1 })
		replace(24, { 1 })
		tick()
		assert.are.equal(0, lvm_models.view({ 14 }).by_key["2"].more)
		local node, chips = render(row)
		assert.are.equal("BoxLayout", node.kind) -- one model no other line uses: hidden
		assert.is_nil(chips)
	end)

	it("logs whether the row shows what the engine has", function()
		render(lvm_models.update(list({ 11, 12, 13, 14 }, {})))
		lvm_models.debug({ action = "verify" })
		assert.truthy(world.log[#world.log]:find("models=3+2 1+1 ok", 1, true))
		replace(12, { 2 })
		lvm_models.debug({ action = "verify" })
		assert.truthy(world.log[#world.log]:find("models=2+2 2+1 STALE", 1, true))
		tick()
		lvm_models.debug({ action = "verify" })
		assert.truthy(world.log[#world.log]:find("ok", 1, true))
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
		---@param self spec.lvm_models.Ref<game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState> see list()
		---@param value game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState
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
		lvm_models.view({ 11, 14 })
		local reads = calls.components
		assert.are.equal(5, lvm_models.pull_model("1"))
		-- one pass over the fleet (11, 14 and the 7 vehicles of other lines), then make_state's 6 entries
		assert.are.equal(2 + 7 + 6, calls.components - reads)
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
		local _node, chips, pull = render(lvm_models.update(list({ 11, 12 }, { 14 })))
		assert.are.equal(2, #chips)
		assert.are.equal("vehicle-button, selected", chips[1].params.meta.class)
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
