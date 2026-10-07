--- Line Manager: a search field above the vehicle list (feature vehicle_search). It finds vehicles by
-- their name, their model and their line, with the game's own text test (lang_util.stringContains,
-- as the Line Manager's line search). The rules are in core/vehicle_search.lua: the search narrows the
-- Line Manager's vehicle list itself (vehicleManagerStateRef), so its "select all", its counts and
-- every action reach exactly the vehicles shown; the hidden ones wait in a stash and come back,
-- unselected, when the search is cleared. With no match the list keeps its vehicles, none selected,
-- and shows "No matches found".
--
-- The list is the Line Manager's state, which the base writes as well. What the search hid belongs to
-- a list as long as the list goes on: the manager's own api calls that add vehicles, take them off
-- or clear the list are wrapped and keep the stash in step (taken off: out of the stash too; cleared:
-- stash emptied); any other write goes on from the list when it keeps every vehicle the list had
-- (a selection change, sold vehicles gone), and replaces it otherwise (another line selected). When
-- the Line Manager closes during a search, the search ends and its list gets the hidden vehicles back
-- the next time it shows, if it is still that list.
-- Rendered by lvm_tweaks.lua's VehicleList, the recipe the search lives in; with a gamepad there is no
-- field, as the base shows none.
-- @module ui_overhaul.gui.lvm_search
local builtin = require("::/gui/main/builtin.lua")
local lang_util = require("::/scripts/lang_util.tl")
local entity_util = require("::/scripts/entity_util.tl")
local vehicle_search = require("/ui_overhaul/core/vehicle_search.lua")
local lvm_models = require("/ui_overhaul/gui/lvm_models.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")

---@class uo.gui.lvm_search
local lvm_search = {}

---@alias uo.gui.lvm_search.State game.gui.line_vehicle_mgmt.manager_window.VehicleManagerState
---@alias uo.gui.lvm_search.ListParams game.gui.line_vehicle_mgmt.vehicle_list_react_util.VehicleListParams

---The search of the open Line Manager (there is one at a time).
---@class uo.gui.lvm_search.Session
---@field text string what the player typed
---@field stash game.scripts.entity_util.EntityAndRevision[] vehicles the search hid from the list
---@field owner? uo.gui.lvm_search.State the list state the stash belongs to
---@field narrowed? uo.gui.lvm_search.State the state this module set last
---@field none boolean nothing matches: the list shows no row
---@field dirty boolean the text changed since `narrowed`

---@type uo.gui.lvm_search.Session
local session = { text = "", stash = {}, none = false, dirty = false }

local report = guard.reporter("vehicle search: ")

---@param entry game.scripts.entity_util.EntityAndRevision
---@return boolean
local function alive(entry)
	return not entity_util.entityChanged0(entry) and entity_util.isOwnedByPlayer(entry.entity)
end

---@param state uo.gui.lvm_search.State
---@return uo.core.vehicle_search.Lists
local function lists(state)
	return { selected = state.vehicleListEntitiesSelected or {}, unselected = state.vehicleListEntitiesUnselected or {} }
end

--- What the search looks at in a vehicle: its name, its model's name and its line's name.
---@param entity Engine.Entity
---@return string[]
function lvm_search.fields(entity)
	local fields = { api.engine.util.getEntityName(entity) or "" }
	local ids = lvm_models.read_ids(entity)
	if ids then fields[#fields + 1] = lvm_models.model_name(ids, lvm_models.name_of) end
	local tv = api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv and tv.line and tv.line >= 0 and api.engine.entityExists(tv.line) then
		fields[#fields + 1] = api.engine.util.getEntityName(tv.line) or ""
	end
	return fields
end

--- A match test for `text`, reading each vehicle once.
---@param text string
---@return fun(entity: Engine.Entity): boolean
local function matcher(text)
	local wanted = text:match("^%s*(.-)%s*$") ---@type string
	local known = {} ---@type table<Engine.Entity, boolean>
	return function(entity)
		if known[entity] == nil then
			local ok, found = pcall(vehicle_search.matches, wanted, lvm_search.fields(entity), lang_util.stringContains)
			known[entity] = ok and found == true
		end
		return known[entity]
	end
end

--- Whether lists `a` and `b` hold the same vehicles with the same selection.
---@param a uo.core.vehicle_search.Lists
---@param b uo.core.vehicle_search.Lists
---@return boolean
local function same(a, b)
	if #a.selected ~= #b.selected or #a.unselected ~= #b.unselected then return false end
	local selected = {} ---@type table<integer, boolean>
	for _i, entry in ipairs(a.selected) do selected[entry.entity] = true end
	for _i, entry in ipairs(a.unselected) do selected[entry.entity] = false end
	for _i, entry in ipairs(b.selected) do
		if selected[entry.entity] ~= true then return false end
	end
	for _i, entry in ipairs(b.unselected) do
		if selected[entry.entity] ~= false then return false end
	end
	return true
end

---@param ref react.Ref<uo.gui.lvm_search.State>
---@param result uo.core.vehicle_search.Lists
---@return uo.gui.lvm_search.State
local function write(ref, result)
	local state = lvm_models.make_state(result.selected, result.unselected)
	ref:set(state)
	return state
end

local function forget()
	session.stash, session.owner, session.narrowed, session.none, session.dirty = {}, nil, nil, false, false
end

--- Puts the hidden vehicles back into the list (unselected) if the list is still the one they were
-- hidden from, and forgets them.
---@param ref react.Ref<uo.gui.lvm_search.State>
local function restore(ref)
	local state = ref:get()
	if #session.stash > 0 and state ~= nil and state == session.owner then
		write(ref, vehicle_search.restore(lists(state), session.stash))
	end
	forget()
end

--- Brings the Line Manager's list in line with the search; each step, from the list's recipe.
---@param params uo.gui.lvm_search.ListParams
function lvm_search.step(params)
	local ref = params.commonParams.vehicleManagerStateRef
	local state = ref:get()
	if state == nil then return end
	if not vehicle_search.active(session.text) then
		if session.owner ~= nil then restore(ref) end
		return
	end
	if state == session.narrowed and not session.dirty then return end
	local goes_on = state == session.owner
		or (session.owner ~= nil and vehicle_search.continues(lists(session.owner), lists(state), alive))
	local result = vehicle_search.narrow(lists(state), goes_on and session.stash or {}, matcher(session.text))
	session.stash, session.none, session.dirty = result.stash, result.none, false
	-- unchanged: nothing to write (a write makes the Line Manager render again)
	local new_state = same(result, lists(state)) and state or write(ref, result)
	session.owner, session.narrowed = new_state, new_state
end

--- The text typed; the next step applies it.
---@param text string
function lvm_search.set_text(text)
	if text == session.text then return end
	session.text, session.dirty = text or "", true
end

--- The current search text.
---@return string
function lvm_search.text()
	return session.text
end

--- The list's vehicles to show as rows: none while nothing matches.
---@param vehicles Engine.Entity[]
---@return Engine.Entity[]
function lvm_search.shown(vehicles)
	if session.none and vehicle_search.active(session.text) then return {} end
	return vehicles
end

--- When the list's recipe goes (the Line Manager closes, or its list empties) the search ends. Nothing
-- is written while the recipe goes: the next step of the list, without a search, puts the hidden
-- vehicles back if the list is still the one they were hidden from.
function lvm_search.unmount()
	session.text, session.dirty = "", false
end

---@type table<function, boolean>
local own = setmetatable({}, { __mode = "k" }) -- the api wrappers this module made

--- Wraps the vehicle manager's api calls that change the list, so the stash keeps up with them.
---@param params uo.gui.lvm_search.ListParams
function lvm_search.wrap_api(params)
	local manager = params.managerRef and params.managerRef:get()
	local vm_api = manager and manager:getApi()
	if type(vm_api) ~= "table" then return end
	local ref = params.commonParams.vehicleManagerStateRef
	local fields = vm_api --[[@as table<string, function?>]]
	---@param name string
	---@param after fun(entities?: Engine.Entity[])
	local function wrap(name, after)
		local original = fields[name]
		if type(original) ~= "function" or own[original] then return end
		---@param entities? Engine.Entity[]
		---@param ... any passed on unchanged to the previous function
		---@return any ... whatever the previous function returns
		local wrapper = function(entities, ...)
			local results = table.pack(original(entities, ...))
			if session.owner ~= nil then
				local ok, err = pcall(after, entities)
				if not ok then report(name, err) end
			end
			return table.unpack(results, 1, results.n)
		end
		own[wrapper] = true
		fields[name] = wrapper
	end
	-- the list goes on: what they add is matched on the next step
	wrap("addVehiclesToVehicleListAndSelect", function() session.owner = ref:get() end)
	wrap("removeVehiclesFromVehicleList", function(entities)
		session.stash = vehicle_search.without(session.stash, entities or {}, alive)
		session.owner = ref:get()
	end)
	wrap("clearVehicleList", function()
		session.stash = {}
		session.owner = ref:get()
	end)
end

--- testbench: the search and the list as one log line, "text=... selected=N unselected=N hidden=N
-- none=B rows=N names=a,b".
---@param params uo.gui.lvm_search.ListParams
---@return string
function lvm_search.describe(params)
	local state = params.commonParams.vehicleManagerStateRef:get()
	local listed = state and lists(state) or { selected = {}, unselected = {} }
	local rows = lvm_search.shown(params.vehicles or {})
	local names = {} ---@type string[]
	for i, entity in ipairs(rows) do names[i] = api.engine.util.getEntityName(entity) or tostring(entity) end
	table.sort(names)
	return string.format("text=%q selected=%d unselected=%d hidden=%d none=%s rows=%d names=%s", session.text,
		#listed.selected, #listed.unselected, #session.stash, tostring(session.none), #rows, table.concat(names, ","))
end

--- The search field, or nil with a gamepad (the base shows no search field then either).
---@param params uo.gui.lvm_search.ListParams
---@param on_change fun() re-renders the list's recipe
---@return react.TreeNodeId?
function lvm_search.field(params, on_change)
	local gamepad = params.commonParams.gamepadInputModeState
	if gamepad and gamepad:old() then return nil end
	---@param text string
	local function set(text)
		lvm_search.set_text(text)
		on_change()
	end
	return builtin.Component{
		meta = { class = "uio-vehicle-search" },
		layout = builtin.BoxLayout{ children = {
			builtin.TextInputField{
				-- the game's search field (statistics_react_util.createSearchField), with a class of its own
				meta = { class = "font-scale-body, search, uio-vehicle-search-field" },
				placeholderText = _("Search..."),
				value = session.text,
				onValueChange = set,
				onTyping = set,
			},
		} },
	}
end

--- "No matches found" while nothing matches, else nil.
---@return react.TreeNodeId?
function lvm_search.no_match()
	if not (session.none and vehicle_search.active(session.text)) then return nil end
	-- one Line Manager at a time: the id is unique (the testbench looks it up)
	return builtin.Component{
		meta = { class = "uio-vehicle-search-none", id = "uio.lvm.search.none" },
		layout = builtin.BoxLayout{ children = {
			builtin.TextView{ meta = { class = "font-scale-body, uio-vehicle-search-none-text" }, text = _("No matches found") },
		} },
	}
end

return lvm_search
