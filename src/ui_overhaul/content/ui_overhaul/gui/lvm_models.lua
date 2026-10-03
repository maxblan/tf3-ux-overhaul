--- Line Manager vehicle models (backlog: change one model across many lines):
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
-- @module ui_overhaul.gui.lvm_models
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local lang_util = require("::/scripts/lang_util.tl")
local entity_util = require("::/scripts/entity_util.tl")
local vehicle_react_util = require("::/gui/line_vehicle_mgmt/vehicle_react_util.tl")

local lvm_models = {}

--- Latest VehicleList parameters and their model view; one Line Manager exists at a time.
local live = { params = nil, view = nil }
lvm_models.live = live

local cache = { signature = nil, view = nil }
local names = {} -- model id -> name

local function report(what, err)
	debugPrint("[ui_overhaul] Line Manager models: ", what, ": ", tostring(err))
end

-- Pure helpers ------------------------------------------------------------------------------------

--- Key of a vehicle's model: the id for one part, else the sorted "id x count" composition.
function lvm_models.model_key(ids)
	if #ids == 1 then return tostring(ids[1]) end
	local counts, order = {}, {}
	for _i, id in ipairs(ids) do
		if not counts[id] then order[#order + 1] = id end
		counts[id] = (counts[id] or 0) + 1
	end
	table.sort(order)
	local parts = {}
	for i, id in ipairs(order) do parts[i] = string.format("%dx%d", id, counts[id]) end
	return table.concat(parts, ",")
end

--- Display name like the vehicle window's: runs of one model as "Name (3x)", joined by "\n + ".
function lvm_models.model_name(ids, name_of)
	local result, last, run = "", nil, 0
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
function lvm_models.signature(vehicles)
	local sorted = {}
	for i, v in ipairs(vehicles) do sorted[i] = v end
	table.sort(sorted)
	return table.concat(sorted, ",")
end

--- Groups the vehicles by model, most vehicles first. `read_ids(v)` returns the model ids or nil.
-- Returns groups ({ key, ids, name, vehicles, count, more = 0 }) and a map vehicle -> key.
function lvm_models.group(vehicles, read_ids, name_of)
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
function lvm_models.target(groups, by_entity, by_key, selected)
	local key, one_model = nil, true
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
function lvm_models.exact_key(by_entity, by_key, selected)
	local key = nil
	for _i, v in ipairs(selected) do
		local k = by_entity[v]
		if not k or (key and k ~= key) then return nil end
		key = k
	end
	if key and by_key[key].count == #selected then return key end
	return nil
end

--- The row shows for two or more models, or for one model that other lines use too.
function lvm_models.row_visible(groups)
	return #groups >= 2 or (#groups == 1 and groups[1].more > 0)
end

-- Engine reads ------------------------------------------------------------------------------------

local function transport_vehicle(v)
	if not api.engine.entityExists(v) then return nil end
	return api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
end

--- Model ids of a vehicle's parts (vehicle_util.GetVehicleModelIds), or nil.
function lvm_models.read_ids(v)
	local tv = transport_vehicle(v)
	if not tv then return nil end
	local ids = {}
	for i, part in ipairs(tv.transportVehicleConfig.vehicles) do ids[i] = part.part.modelId end
	return ids
end

function lvm_models.name_of(id)
	if names[id] == nil then
		local model = api.res.modelRep.get(id)
		local desc = model and model.metadata and model.metadata.description
		names[id] = desc and desc.name or tostring(id)
	end
	return names[id]
end

--- Vehicles on the player's lines, except those in `skip` (a set).
local function line_vehicles(skip)
	local result = {}
	local system = api.engine.system
	for _i, line in ipairs(system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		for _j, v in ipairs(system.transportVehicleSystem.getLineVehicles(line)) do
			if not skip[v] then result[#result + 1] = v end
		end
	end
	return result
end

--- Vehicles of model `key` on the player's lines that are not in `skip`.
function lvm_models.scan(key, skip)
	local result = {}
	for _i, v in ipairs(line_vehicles(skip or {})) do
		local ids = lvm_models.read_ids(v)
		if ids and #ids > 0 and lvm_models.model_key(ids) == key then result[#result + 1] = v end
	end
	return result
end

--- Model view of a vehicle list, recomputed only when the list's members change.
function lvm_models.view(vehicles)
	local signature = lvm_models.signature(vehicles)
	if cache.signature == signature then return cache.view end
	local groups, by_entity, by_key = lvm_models.group(vehicles, lvm_models.read_ids, lvm_models.name_of)
	if #groups > 0 then
		for _i, v in ipairs(line_vehicles(by_entity)) do
			local ids = lvm_models.read_ids(v)
			local group = ids and #ids > 0 and by_key[lvm_models.model_key(ids)]
			if group then group.more = group.more + 1 end
		end
	end
	cache.signature = signature
	cache.view = { groups = groups, by_entity = by_entity, by_key = by_key }
	return cache.view
end

--- Lines of the vehicles (en route or at a terminal), counted up to `limit`.
function lvm_models.line_count(vehicles, limit)
	local lines, count = {}, 0
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
function lvm_models.make_state(selected, unselected)
	local carriers_map = {}
	local function keep(entries)
		local result = {}
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
	local state = { vehicleListEntitiesSelected = keep(selected), vehicleListEntitiesUnselected = keep(unselected) }
	local carriers = {}
	for carrier in pairs(carriers_map) do carriers[#carriers + 1] = carrier end
	state.carriers = carriers
	return state
end

local function close_vehicle_store(params)
	local ok, err = pcall(function()
		local manager = params.managerRef and params.managerRef:get()
		if manager then manager:getApi().closeVehicleStore() end
	end)
	if not ok then report("closing the vehicle store", err) end
end

--- Selects exactly the vehicles in the set `wanted`; vehicles in `add` that are not in the list yet
-- are added. Returns the number of selected vehicles.
function lvm_models.select_set(params, wanted, add)
	close_vehicle_store(params)
	local ref = params.commonParams.vehicleManagerStateRef
	local state = ref:get()
	local selected, unselected, seen = {}, {}, {}
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

local function set_of(list)
	local result = {}
	for _i, v in ipairs(list) do result[v] = true end
	return result
end

--- Selects exactly the listed vehicles of model `key`.
function lvm_models.select_model(key)
	local group = live.view and live.view.by_key[key]
	if not (group and live.params) then return 0 end
	return lvm_models.select_set(live.params, set_of(group.vehicles), {})
end

--- Adds the vehicles of model `key` from all lines to the list and selects exactly that model.
function lvm_models.pull_model(key)
	local group = live.view and live.view.by_key[key]
	if not (group and live.params) then return 0 end
	local listed = set_of(group.vehicles)
	local found = lvm_models.scan(key, listed)
	for _i, v in ipairs(found) do listed[v] = true end
	return lvm_models.select_set(live.params, listed, found)
end

--- Shift+click on a listed vehicle: selects all listed vehicles of its model. Returns true if done.
function lvm_models.select_same_model(entity)
	local key = live.view and live.view.by_entity[entity]
	if not key then return false end
	lvm_models.select_model(key)
	return true
end

function lvm_models.shift_held()
	local ok, held = pcall(function() return api.gui.inputAction.modifierOnlyActionIsActive("IA_PRECISION_MODE") end)
	return ok and held == true
end

local function selected_vehicles(params)
	local result = {}
	local state = params.commonParams.vehicleManagerStateRef:get()
	for i, ear in ipairs(state and state.vehicleListEntitiesSelected or {}) do result[i] = ear.entity end
	return result
end

-- Row ---------------------------------------------------------------------------------------------

local function on_select(key)
	local ok, err = pcall(lvm_models.select_model, key)
	if not ok then report("selecting a model", err) end
end

local function on_pull(key)
	local ok, err = pcall(lvm_models.pull_model, key)
	if not ok then report("adding a model from all lines", err) end
end

local function pull_button(target)
	local tooltip, enabled
	if not target then
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

local function render_row(p)
	local chips = {}
	for _i, group in ipairs(p.groups) do
		local key = group.key
		chips[#chips + 1] = builtin.Button{
			meta = {
				localKey = "model-" .. key,
				class = key == p.exact_key and "vehicle-button, selected" or "vehicle-button",
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
					pull_button(p.target),
				},
			},
		},
	} }
end

-- Recipe bodies run later than the call that creates their node, so the body guards itself.
local Row = react.RegisterRecipe("UioLvmModels", function(p)
	local ok, node = pcall(render_row, p)
	if ok then return node end
	report("row", node)
	return builtin.BoxLayout{}
end)

--- Called by the VehicleList wrapper on every render: records the parameters and returns the row
-- node, or nil while it is hidden.
function lvm_models.update(params)
	live.params = params
	live.view = lvm_models.view(params.vehicles or {})
	local view = live.view
	if not lvm_models.row_visible(view.groups) then return nil end
	local selected = selected_vehicles(params)
	return Row{
		meta = { localKey = "uio-lvm-models" },
		groups = view.groups,
		exact_key = lvm_models.exact_key(view.by_entity, view.by_key, selected),
		target = lvm_models.target(view.groups, view.by_entity, view.by_key, selected),
	}
end

--- Testbench ("uio.debug.lvm_models", { action = "select" | "pull", index = 1 }): acts on the
-- index-th model of the open list and logs the selection count against the expected one.
function lvm_models.debug(param)
	param = type(param) == "table" and param or {}
	local action, index = param.action or "select", param.index or 1
	local group = live.view and live.view.groups[index]
	if not (group and live.params) then
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
		(group.name:gsub("\n", " ")), selected, expected, #live.view.groups, selected == expected and "ok" or "MISMATCH"))
end

return lvm_models
