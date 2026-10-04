--- Line Manager vehicle models, for changing one model across many lines:
--   * a row above the vehicle list with one button per model in the list (the base vehicle icon and
--     count); clicking one selects exactly the vehicles of that model
--   * "In all lines" adds every vehicle of the selected model from all the player's lines to the
--     list and selects exactly those, so Replace or Modify reaches them in one go
--   * Shift+click on a vehicle row selects all listed vehicles of the same model (lvm_tweaks.lua)
-- The row is hidden while the list holds one model that no other line uses.
-- A model is one model id for single vehicles; for trains it is the composition (model ids with
-- counts, in any order), the rule the vehicle store uses to replace several vehicles at once
-- (vehicle_store_window.tl:2844-2863).
-- The selection is written to the Line Manager's vehicleManagerStateRef the way its master check
-- box does (manager_window.tl:4946-4964), filtered like makeVehicleManagerState (local there,
-- manager_window.tl:1462-1505).
-- A Replace keeps the vehicle ids (makeVehicleReplaceCmd) and other lines' fleets change without the
-- list changing, so the row re-reads the models on a timer, as the base VehicleWidget does, and
-- every action re-reads them before it selects anything.
-- @module ui_overhaul.gui.lvm_models
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local table_util = require("::/scripts/table_util.tl")
local entity_util = require("::/scripts/entity_util.tl")
local vehicle_react_util = require("::/gui/line_vehicle_mgmt/vehicle_react_util.tl")

---@class uo.gui.lvm_models
local lvm_models = {}

---@alias uo.gui.lvm_models.ListParams game.gui.line_vehicle_mgmt.vehicle_list_react_util.VehicleListParams

---The vehicles of one model in a list.
---@class uo.gui.lvm_models.Group
---@field key string model_key of `ids`
---@field ids integer[] model ids of the parts
---@field name string
---@field vehicles Engine.Entity[]
---@field count integer
---@field more integer vehicles of this model on other lines

---What read_fleet found: model key per listed vehicle, model ids per key, and per key the vehicles
---of that model on the player's lines that are not listed.
---@class uo.gui.lvm_models.Fleet
---@field keys table<Engine.Entity, string>
---@field ids table<string, integer[]>
---@field others table<string, Engine.Entity[]>

---@class uo.gui.lvm_models.View
---@field groups uo.gui.lvm_models.Group[]
---@field pending boolean the other lines are not read yet: every `more` is 0 until the row's timer reads them
---@field by_entity table<Engine.Entity, string> vehicle -> model key
---@field by_key table<string, uo.gui.lvm_models.Group>

---@class uo.gui.lvm_models.RowParams: react.Param
---@field vehicles Engine.Entity[]
---@field selected Engine.Entity[]

---The testbench event's param.
---@class uo.gui.lvm_models.DebugParam
---@field action? "select"|"pull"|"verify"
---@field index? integer

local REFRESH = 2.0 -- seconds; a refresh reads the listed vehicles' models
-- Every this many refreshes the other lines are read too (every vehicle on the player's lines), and
-- whenever a listed vehicle's model changed.
lvm_models.OTHERS_EVERY = 5

--- Latest VehicleList parameters; one Line Manager exists at a time.
---@type { params: uo.gui.lvm_models.ListParams? }
local live = { params = nil }
lvm_models.live = live

--- The model view of the latest list. `fleet` is what the engine said (read_fleet), `view` is built
-- from it on demand; `stamp` changes whenever a refresh found a different fleet. `signature`,
-- `vehicles` and `fleet` are set together.
---@class uo.gui.lvm_models.Cache
---@field signature? string
---@field vehicles? Engine.Entity[]
---@field fleet? uo.gui.lvm_models.Fleet
---@field view? uo.gui.lvm_models.View
---@field stamp integer
---@field pending boolean `fleet.others` is not read yet
---@field ticks integer refreshes since the other lines were last read
local cache = { signature = nil, vehicles = nil, fleet = nil, view = nil, stamp = 0, pending = false, ticks = 0 }
local names = {} ---@type table<integer, string> model id -> name

---@param what string
---@param err any the pcall error, any value
local function report(what, err)
	debugPrint("[ui_overhaul] Line Manager models: ", what, ": ", tostring(err))
end

-- Pure helpers ------------------------------------------------------------------------------------

--- Key of a vehicle's model: the id for one part, else the sorted "id x count" composition.
---@param ids integer[]
---@return string
function lvm_models.model_key(ids)
	if #ids == 1 then return tostring(ids[1]) end
	local counts, order = {}, {} ---@type table<integer, integer>, integer[]
	for _i, id in ipairs(ids) do
		if not counts[id] then order[#order + 1] = id end
		counts[id] = (counts[id] or 0) + 1
	end
	table.sort(order)
	local parts = {} ---@type string[]
	for i, id in ipairs(order) do parts[i] = string.format("%dx%d", id, counts[id]) end
	return table.concat(parts, ",")
end

--- Display name like the vehicle window's: runs of one model as "Name (3x)", joined by "\n + ".
---@param ids integer[]
---@param name_of fun(id: integer): string
---@return string
function lvm_models.model_name(ids, name_of)
	local result, last, run = "", nil, 0 ---@type string, string?, integer
	local function close_run()
		if run > 1 then result = result .. " (" .. tostring(run) .. "x)" end
	end
	for _i, id in ipairs(ids) do
		local name = name_of(id)
		if name == last then
			run = run + 1
		else
			close_run()
			result = result == "" and name or (result .. "\n + " .. name)
			last, run = name, 1
		end
	end
	close_run()
	return result
end

--- Order-independent identity of a vehicle list.
---@param vehicles Engine.Entity[]
---@return string
function lvm_models.signature(vehicles)
	local sorted = {} ---@type Engine.Entity[]
	for i, v in ipairs(vehicles) do sorted[i] = v end
	table.sort(sorted)
	return table.concat(sorted, ",")
end

--- Groups the vehicles by model, most vehicles first. `read_ids(v)` returns the model ids or nil.
-- Returns groups ({ key, ids, name, vehicles, count, more = 0 }) and a map vehicle -> key.
---@param vehicles Engine.Entity[]
---@param read_ids fun(v: Engine.Entity): integer[]?
---@param name_of fun(id: integer): string
---@return uo.gui.lvm_models.Group[] groups
---@return table<Engine.Entity, string> by_entity
---@return table<string, uo.gui.lvm_models.Group> by_key
function lvm_models.group(vehicles, read_ids, name_of)
	---@type table<string, uo.gui.lvm_models.Group>, uo.gui.lvm_models.Group[], table<Engine.Entity, string>
	local by_key, groups, by_entity = {}, {}, {}
	for _i, v in ipairs(vehicles) do
		local ids = read_ids(v)
		if ids and #ids > 0 then
			local key = lvm_models.model_key(ids)
			local group = by_key[key]
			if not group then
				group = { key = key, ids = ids, name = lvm_models.model_name(ids, name_of), vehicles = {}, count = 0, more = 0 }
				by_key[key] = group
				groups[#groups + 1] = group
			end
			group.vehicles[#group.vehicles + 1] = v
			group.count = group.count + 1
			by_entity[v] = key
		end
	end
	table.sort(groups, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		if a.name ~= b.name then return a.name < b.name end
		return a.key < b.key
	end)
	return groups, by_entity, by_key
end

--- The model the "In all lines" button acts on: the one model of the selection, else the list's
-- only model. `selected` is a list of vehicles.
---@param groups uo.gui.lvm_models.Group[]
---@param by_entity table<Engine.Entity, string>
---@param by_key table<string, uo.gui.lvm_models.Group>
---@param selected Engine.Entity[]
---@return uo.gui.lvm_models.Group?
function lvm_models.target(groups, by_entity, by_key, selected)
	local key, one_model = nil, true ---@type string?, boolean
	for _i, v in ipairs(selected) do
		local k = by_entity[v]
		if not k or (key and k ~= key) then one_model = false break end
		key = k
	end
	if one_model and key then return by_key[key] end
	if #groups == 1 then return groups[1] end
	return nil
end

--- Key of the group whose vehicles are exactly the selection, or nil.
---@param by_entity table<Engine.Entity, string>
---@param by_key table<string, uo.gui.lvm_models.Group>
---@param selected Engine.Entity[]
---@return string?
function lvm_models.exact_key(by_entity, by_key, selected)
	local key = nil ---@type string?
	for _i, v in ipairs(selected) do
		local k = by_entity[v]
		if not k or (key and k ~= key) then return nil end
		key = k
	end
	if key and by_key[key].count == #selected then return key end
	return nil
end

--- The row shows for two or more models, or for one model that other lines use too.
---@param groups uo.gui.lvm_models.Group[]
---@return boolean
function lvm_models.row_visible(groups)
	return #groups >= 2 or (#groups == 1 and groups[1].more > 0)
end

-- Engine reads ------------------------------------------------------------------------------------

---@param v Engine.Entity
---@return Engine.Component.TransportVehicle?
local function transport_vehicle(v)
	if not api.engine.entityExists(v) then return nil end
	return api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
end

--- Model ids of a vehicle's parts (vehicle_util.GetVehicleModelIds), or nil.
---@param v Engine.Entity
---@return integer[]?
function lvm_models.read_ids(v)
	local tv = transport_vehicle(v)
	if not tv then return nil end
	local ids = {} ---@type integer[]
	for i, part in ipairs(tv.transportVehicleConfig.vehicles) do ids[i] = part.part.modelId end
	return ids
end

---@param id integer
---@return string
function lvm_models.name_of(id)
	if names[id] == nil then
		local model = api.res.modelRep.get(id)
		local desc = model and model.metadata and model.metadata.description
		names[id] = desc and desc.name or tostring(id)
	end
	return names[id]
end

--- Vehicles on the player's lines, except those in `skip` (a set).
---@param skip table<Engine.Entity, string>
---@return Engine.Entity[]
local function line_vehicles(skip)
	local result = {} ---@type Engine.Entity[]
	local system = api.engine.system
	for _i, line in ipairs(system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		for _j, v in ipairs(system.transportVehicleSystem.getLineVehicles(line)) do
			if not skip[v] then result[#result + 1] = v end
		end
	end
	return result
end

--- The listed vehicles' models (engine reads of the list only): a fleet whose `others` lists are
-- still empty (read_others fills them).
---@param vehicles Engine.Entity[]
---@return uo.gui.lvm_models.Fleet
local function read_keys(vehicles)
	---@type table<Engine.Entity, string>, table<string, integer[]>, table<string, Engine.Entity[]>
	local keys, ids_of, others = {}, {}, {}
	for _i, v in ipairs(vehicles) do
		local ids = lvm_models.read_ids(v)
		if ids and #ids > 0 then
			local key = lvm_models.model_key(ids)
			keys[v] = key
			ids_of[key] = ids_of[key] or ids
			others[key] = {}
		end
	end
	return { keys = keys, ids = ids_of, others = others }
end

--- Fills `fleet.others`: reads every vehicle on the player's lines.
---@param fleet uo.gui.lvm_models.Fleet
local function read_others(fleet)
	if not next(fleet.others) then return end
	for _i, v in ipairs(line_vehicles(fleet.keys)) do
		local ids = lvm_models.read_ids(v)
		local found = ids and #ids > 0 and fleet.others[lvm_models.model_key(ids)]
		if found then found[#found + 1] = v end
	end
end

--- What the engine says about a vehicle list (engine reads only, so it can run in a timer
-- callback): `keys` maps each listed vehicle to its model key, `ids` each key to its model ids and
-- `others` each key to the vehicles of that model on the player's lines that are not listed
-- ("In all lines" adds those).
---@param vehicles Engine.Entity[]
---@return uo.gui.lvm_models.Fleet
function lvm_models.read_fleet(vehicles)
	local fleet = read_keys(vehicles)
	read_others(fleet)
	return fleet
end

---@param vehicles Engine.Entity[]
---@param fleet uo.gui.lvm_models.Fleet
---@param pending boolean
---@return uo.gui.lvm_models.View
local function build_view(vehicles, fleet, pending)
	local groups, by_entity, by_key = lvm_models.group(vehicles, function(v)
		local key = fleet.keys[v]
		return key and fleet.ids[key]
	end, lvm_models.name_of)
	for key, group in pairs(by_key) do group.more = #(fleet.others[key] or {}) end
	return { groups = groups, by_entity = by_entity, by_key = by_key, pending = pending }
end

--- Model view of a vehicle list. When the list's members change, only the listed vehicles are read
-- (this runs while the Line Manager renders); the other lines follow with refresh(), from the row's
-- timer or before an action.
---@param vehicles Engine.Entity[]
---@return uo.gui.lvm_models.View
function lvm_models.view(vehicles)
	local signature = lvm_models.signature(vehicles)
	if cache.signature ~= signature then
		local copy = {} ---@type Engine.Entity[]
		for i, v in ipairs(vehicles) do copy[i] = v end
		-- the signature only once the fleet is read: a failed read leaves the old list unmatched
		local fleet = read_keys(copy)
		cache.signature, cache.vehicles, cache.fleet, cache.view = signature, copy, fleet, nil
		cache.pending, cache.ticks = true, 0
	end
	-- set together with the signature, which matches here
	local listed, fleet = cache.vehicles --[[@as Engine.Entity[] ]], cache.fleet --[[@as uo.gui.lvm_models.Fleet]]
	if not cache.view then cache.view = build_view(listed, fleet, cache.pending) end
	return cache.view
end

--- Re-reads the fleet of the cached list (engine reads only, so it can run in a timer callback)
-- and drops the view if the fleet changed: a vehicle was replaced in place, or other lines gained
-- or lost vehicles of a listed model. The other lines are read when `full`, when they were not read
-- yet, when a listed vehicle's model changed and every OTHERS_EVERY calls. Returns the stamp, which
-- changes with every drop.
---@param full? boolean
---@return integer
function lvm_models.refresh(full)
	if not cache.vehicles then return cache.stamp end
	local old = cache.fleet --[[@as uo.gui.lvm_models.Fleet]] -- set together with vehicles
	local fleet = read_keys(cache.vehicles)
	cache.ticks = cache.ticks + 1
	local models_changed = not (table_util.deepEquals(fleet.keys, old.keys) and table_util.deepEquals(fleet.ids, old.ids))
	if not (full or cache.pending or models_changed or cache.ticks >= lvm_models.OTHERS_EVERY) then
		return cache.stamp
	end
	read_others(fleet)
	cache.ticks = 0
	if cache.pending or not table_util.deepEquals(fleet, old) then
		cache.fleet, cache.view, cache.pending = fleet, nil, false
		cache.stamp = cache.stamp + 1
	end
	return cache.stamp
end

--- The open list's view as the engine has it now, for an action that is about to select vehicles.
-- Reads the listed vehicles and the other lines now: an action must not act on an old reading.
---@return uo.gui.lvm_models.View?
local function current_view()
	if not live.params then return nil end
	local vehicles = live.params.vehicles or {}
	lvm_models.view(vehicles) -- a new list: its models
	lvm_models.refresh(true) -- and the other lines, as they are now
	return lvm_models.view(vehicles)
end

--- Lines of the vehicles (en route or at a terminal), counted up to `limit`.
---@param vehicles Engine.Entity[]
---@param limit? integer
---@return integer
function lvm_models.line_count(vehicles, limit)
	local lines, count = {}, 0 ---@type table<Engine.Entity, boolean>, integer
	local states = api.type.enum.TransportVehicleState
	for _i, v in ipairs(vehicles) do
		local tv = transport_vehicle(v)
		if tv and (tv.state == states.EN_ROUTE or tv.state == states.AT_TERMINAL) and not lines[tv.line] then
			lines[tv.line] = true
			count = count + 1
			if limit and count >= limit then return count end
		end
	end
	return count
end

-- Selection ---------------------------------------------------------------------------------------

--- makeVehicleManagerState: keeps unchanged, player-owned transport vehicles and collects carriers.
---@param selected game.scripts.entity_util.EntityAndRevision[]
---@param unselected game.scripts.entity_util.EntityAndRevision[]
---@return game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState
function lvm_models.make_state(selected, unselected)
	local carriers_map = {} ---@type table<Carrier, boolean>
	---@param entries game.scripts.entity_util.EntityAndRevision[]
	---@return game.scripts.entity_util.EntityAndRevision[]
	local function keep(entries)
		local result = {} ---@type game.scripts.entity_util.EntityAndRevision[]
		for _i, ear in ipairs(entries) do
			if not entity_util.entityChanged0(ear) and entity_util.isOwnedByPlayer(ear.entity) then
				local tv = api.engine.getComponent(ear.entity, api.type.ComponentType.TRANSPORT_VEHICLE)
				if tv then
					result[#result + 1] = ear
					carriers_map[tv.carrier] = true
				end
			end
		end
		return result
	end
	local kept_selected, kept_unselected = keep(selected), keep(unselected)
	local carriers = {} ---@type Carrier[]
	for carrier in pairs(carriers_map) do carriers[#carriers + 1] = carrier end
	return { vehicleListEntitiesSelected = kept_selected, vehicleListEntitiesUnselected = kept_unselected,
		carriers = carriers }
end

---@param params uo.gui.lvm_models.ListParams
local function close_vehicle_store(params)
	local ok, err = pcall(function()
		local manager = params.managerRef and params.managerRef:get()
		if manager then manager:getApi().closeVehicleStore() end
	end)
	if not ok then report("closing the vehicle store", err) end
end

--- Selects exactly the vehicles in the set `wanted`; vehicles in `add` that are not in the list yet
-- are added. Returns the number of selected vehicles.
---@param params uo.gui.lvm_models.ListParams
---@param wanted table<Engine.Entity, boolean>
---@param add? Engine.Entity[]
---@return integer
function lvm_models.select_set(params, wanted, add)
	close_vehicle_store(params)
	local ref = params.commonParams.vehicleManagerStateRef
	local state = ref:get()
	---@type game.scripts.entity_util.EntityAndRevision[], game.scripts.entity_util.EntityAndRevision[]
	local selected, unselected = {}, {}
	local seen = {} ---@type table<Engine.Entity, boolean>
	---@param entries? game.scripts.entity_util.EntityAndRevision[]
	local function sort(entries)
		for _i, ear in ipairs(entries or {}) do
			seen[ear.entity] = true
			if wanted[ear.entity] then selected[#selected + 1] = ear else unselected[#unselected + 1] = ear end
		end
	end
	sort(state.vehicleListEntitiesSelected)
	sort(state.vehicleListEntitiesUnselected)
	for _i, v in ipairs(add or {}) do
		if not seen[v] then
			seen[v] = true
			local ear = entity_util.makeEntityAndRevision(v)
			if ear then selected[#selected + 1] = ear end
		end
	end
	local new_state = lvm_models.make_state(selected, unselected)
	ref:set(new_state)
	return #new_state.vehicleListEntitiesSelected
end

---@param list Engine.Entity[]
---@return table<Engine.Entity, boolean>
local function set_of(list)
	local result = {} ---@type table<Engine.Entity, boolean>
	for _i, v in ipairs(list) do result[v] = true end
	return result
end

--- Selects exactly the listed vehicles of model `key`.
---@param key string
---@return integer
function lvm_models.select_model(key)
	local view = current_view()
	local group = view and view.by_key[key]
	if not group then return 0 end
	return lvm_models.select_set(live.params, set_of(group.vehicles), {})
end

--- Adds the vehicles of model `key` from all lines to the list and selects exactly that model.
-- The other lines' vehicles come from the fleet current_view() has just read.
---@param key string
---@return integer
function lvm_models.pull_model(key)
	local view = current_view()
	local group = view and view.by_key[key]
	if not group then return 0 end
	local listed = set_of(group.vehicles)
	local fleet = cache.fleet --[[@as uo.gui.lvm_models.Fleet]] -- read with the view current_view() returned
	local found = fleet.others[key] or {}
	for _i, v in ipairs(found) do listed[v] = true end
	return lvm_models.select_set(live.params, listed, found)
end

--- Shift+click on a listed vehicle: selects all listed vehicles of its model. Returns true if done.
---@param entity Engine.Entity
---@return boolean
function lvm_models.select_same_model(entity)
	local view = current_view()
	local key = view and view.by_entity[entity]
	if not (view and key) then return false end
	lvm_models.select_set(live.params, set_of(view.by_key[key].vehicles), {})
	return true
end

---@return boolean
function lvm_models.shift_held()
	local ok, held = pcall(function() return api.gui.inputAction.modifierOnlyActionIsActive("IA_PRECISION_MODE") end)
	return ok and held == true
end

---@param params uo.gui.lvm_models.ListParams
---@return Engine.Entity[]
local function selected_vehicles(params)
	local result = {} ---@type Engine.Entity[]
	local state = params.commonParams.vehicleManagerStateRef:get()
	for i, ear in ipairs(state and state.vehicleListEntitiesSelected or {}) do result[i] = ear.entity end
	return result
end

-- Row ---------------------------------------------------------------------------------------------

---@param key string
local function on_select(key)
	local ok, err = pcall(lvm_models.select_model, key)
	if not ok then report("selecting a model", err) end
end

---@param key string
local function on_pull(key)
	local ok, err = pcall(lvm_models.pull_model, key)
	if not ok then report("adding a model from all lines", err) end
end

---@param target? uo.gui.lvm_models.Group
---@param pending boolean the other lines are not read yet
---@return react.TreeNodeId
local function pull_button(target, pending)
	local tooltip, enabled ---@type string?, boolean
	if pending then
		tooltip, enabled = nil, false -- for a moment, until the row's timer has read the other lines
	elseif not target then
		tooltip, enabled = _("Select vehicles of one model first"), false
	elseif target.more == 0 then
		tooltip, enabled = _("No other line uses this model"), false
	else
		enabled = true
		tooltip = lang_util.format(_("Select all {count} {model} from all lines"),
			{ count = lang_util.formatInt(target.count + target.more), model = target.name })
	end
	return builtin.Button{
		meta = { class = "primary, uio-lvm-models-pull", tooltip = tooltip, enabled = enabled,
			id = "uio.lvm.models.pull" },
		content = builtin.TextView{ meta = { class = "font-scale-body" }, text = _("In all lines") },
		onClick = function() if target then on_pull(target.key) end end,
	}
end

--- Timer callback of the row: re-reads the fleet and returns the cache stamp, so the row renders
-- again when the fleet changed. The first call (at mount, old == nil) reads nothing.
---@param old? integer
---@return integer
local function poll(old)
	if old == nil then return cache.stamp end
	local ok, stamp = pcall(lvm_models.refresh)
	return ok and stamp or old
end

---@param p uo.gui.lvm_models.RowParams
---@return react.TreeNodeId
local function render_row(p)
	engine_react_util.useStepStateTimer(poll, REFRESH)
	local view = lvm_models.view(p.vehicles)
	if not lvm_models.row_visible(view.groups) then return builtin.BoxLayout{} end
	local exact_key = lvm_models.exact_key(view.by_entity, view.by_key, p.selected)
	local chips = {} ---@type react.TreeNodeId[]
	for _i, group in ipairs(view.groups) do
		local key = group.key
		chips[#chips + 1] = builtin.Button{
			meta = {
				localKey = "model-" .. key,
				class = key == exact_key and "vehicle-button, selected" or "vehicle-button",
				tooltip = group.name,
			},
			content = vehicle_react_util.VehicleWidget{ vehicleEntities = group.vehicles, tooltipOverride = group.name },
			onClick = function() on_select(key) end,
		}
	end
	return builtin.BoxLayout{ children = {
		builtin.Component{
			meta = { id = "uio.lvm.models", class = "uio-lvm-models" },
			layout = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Horizontal,
				children = {
					builtin.ScrollArea{
						meta = { class = "uio-lvm-models-scroll" },
						horizontalPolicy = builtin.type.ScrollBarPolicy.Simple,
						verticalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
						content = builtin.Component{ layout = builtin.BoxLayout{
							orientation = builtin.type.Orientation.Horizontal, children = chips } },
					},
					pull_button(lvm_models.target(view.groups, view.by_entity, view.by_key, p.selected), view.pending),
				},
			},
		},
	} }
end

-- Recipe bodies run later than the call that creates their node, so the body guards itself.
---@param p uo.gui.lvm_models.RowParams
---@return react.TreeNodeId
local Row = react.RegisterRecipe("UioLvmModels", function(p)
	local ok, node = pcall(render_row, p)
	if ok then return node end
	report("row", node)
	return builtin.BoxLayout{}
end)

--- Called by the VehicleList wrapper on every render: records the parameters and returns the row
-- node. The row stays mounted while it is hidden (an empty layout), so that its refresh can show it
-- once a Replace or another line makes it useful.
---@param params uo.gui.lvm_models.ListParams
---@return react.TreeNodeId
function lvm_models.update(params)
	live.params = params
	return Row{
		meta = { localKey = "uio-lvm-models" },
		vehicles = params.vehicles or {},
		selected = selected_vehicles(params),
	}
end

--- Testbench ("uio.debug.lvm_models", { action = "select" | "pull" | "verify", index = 1 }): acts on
-- the index-th model of the open list and logs the selection count against the expected one;
-- "verify" logs whether the fleet the row is built from matches the engine (after a Replace, say).
---@param param? uo.gui.lvm_models.DebugParam
function lvm_models.debug(param)
	param = type(param) == "table" and param or {}
	local action, index = param.action or "select", param.index or 1
	if action == "verify" then
		local fleet = cache.vehicles and lvm_models.read_fleet(cache.vehicles)
		local counts = {} ---@type string[]
		for i, group in ipairs(fleet and build_view(cache.vehicles, fleet, false).groups or {}) do
			counts[i] = string.format("%d+%d", group.count, group.more)
		end
		local same = fleet ~= nil and table_util.deepEquals(fleet, cache.fleet)
		debugPrint(string.format("[ui_overhaul] lvm models: verify vehicles=%d models=%s %s",
			cache.vehicles and #cache.vehicles or 0, table.concat(counts, " "), same and "ok" or "STALE"))
		return
	end
	local view = current_view()
	local group = view and view.groups[index]
	if not (view and group) then
		debugPrint("[ui_overhaul] lvm models: no model ", tostring(index))
		return
	end
	local expected = group.count
	if action == "pull" then
		expected = group.count + group.more
		lvm_models.pull_model(group.key)
	else
		lvm_models.select_model(group.key)
	end
	local selected = #selected_vehicles(live.params)
	debugPrint(string.format("[ui_overhaul] lvm models: %s %s selected=%d expected=%d models=%d %s", action,
		(group.name:gsub("\n", " ")), selected, expected, #view.groups, selected == expected and "ok" or "MISMATCH"))
end

return lvm_models
