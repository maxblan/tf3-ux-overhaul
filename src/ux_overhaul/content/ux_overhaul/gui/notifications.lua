--- Notifications (backlog A3, A4), driven from the entry point's per-frame step:
--   A3: once per savegame, switch on the base game's Problem and Caution notification types that a
--       new game starts with hidden (line, station, vehicle problems, overcrowding ...). Afterwards
--       the player's own choice in the notification log is left alone.
--   A4: keep the mod's own persistent notifications (losing line, line without vehicles, vehicle past
--       its lifespan) in sync with the snapshot. They then appear wherever the game shows problems:
--       log, Line Manager icons, entity windows, statistics.
-- Runs in react.onStep (GUI thread), never in a timer callback (see engine/store.lua).
-- @module ux_overhaul.gui.notifications
local entity_util = require("::/scripts/entity_util.tl")
local table_util = require("::/scripts/table_util.tl")
local notification_util = require("::/game_mechanics/notifications/notification_util.tl")
local health = require("/ux_overhaul/core/health.lua")
local store = require("/ux_overhaul/engine/store.lua")

local notifications = {}

local MOD_ID = "ux_overhaul_1"
local STEPS_BETWEEN_SYNCS = 600 -- about 10 s at 60 fps
local FIRST_SYNC_STEP = 120

local steps = 0
local sent = {} -- type -> last sent entitiesAndParam

local function send(name, param)
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", name, param))
end

--- Notification type names ("<res name>" with .res -> .script), as the notification system uses them.
local function type_names()
	local result = {}
	for _i, id in ipairs(api.res.genericRep.getAllOfType("notification")) do
		local name = api.res.genericRep.getName(id):gsub("%.res$", ".script")
		local gui_type = (api.res.genericRep.get(id).data or {}).guiType
		result[#result + 1] = { name = name, gui_type = gui_type }
	end
	return result
end

local function own_type(suffix)
	for _i, entry in ipairs(type_names()) do
		if entry.name:find("ux_overhaul/notifications/" .. suffix .. ".script", 1, true) then return entry.name end
	end
	return nil
end

--- A3: un-hide the base Problem/Caution types once per savegame.
local function unhide_base_problems()
	local saved = api.gui.game.getGuiSaveData(MOD_ID) or {}
	if saved.unhid_problems then return end
	local native = notification_util.externalGetNotificationsStateNative()
	local ignored = native and native:find("ignored")
	ignored = ignored and ignored:asTable() or {}
	if ignored.fully then return end -- a mission controls the notifications
	local types, changed = {}, {}
	for name, value in pairs(ignored.types or {}) do types[name] = value end
	for _i, entry in ipairs(type_names()) do
		if types[entry.name] and (entry.gui_type == "Problem" or entry.gui_type == "Caution") then
			types[entry.name] = nil
			changed[#changed + 1] = entry.name
		end
	end
	if #changed > 0 then
		send("updateIgnoredTypes", { ignoredTypes = types, ignoreFully = false })
	end
	saved.unhid_problems = true
	api.gui.game.setGuiSaveData(MOD_ID, saved)
	debugPrint("[ux_overhaul] showing ", #changed, " hidden problem notification types")
end

local function entity_list(entities)
	local list = {}
	for _i, entity in ipairs(entities) do
		local er = entity_util.makeEntityAndRevision0(entity)
		list[#list + 1] = { entities = { er }, param = { entity = er } }
	end
	return list
end

--- A4: entity lists per own notification type, from the current snapshot.
local function detect(data)
	local losing, empty, old = {}, {}, {}
	for _i, line in ipairs(data.lines or {}) do
		if (line.vehicle_count or 0) == 0 then
			empty[#empty + 1] = line.id
		elseif health.is_losing(line) then
			losing[#losing + 1] = line.id
		end
	end
	for _i, vehicle in ipairs(data.vehicles or {}) do
		if health.is_old(vehicle) then old[#old + 1] = vehicle.id end
	end
	return { line_losing = losing, line_empty = empty, vehicle_old = old }
end

local function sync_own()
	local current = store.get()
	if not current.data then return end
	for suffix, entities in pairs(detect(current.data)) do
		local name = own_type(suffix)
		if name then
			local list = entity_list(entities)
			if not table_util.deepEquals(list, sent[name]) then
				sent[name] = list
				send("updatePersistent", { type = name, entitiesAndParam = list, passOnlyParam = true })
			end
		end
	end
end

--- Called every step by the entry point.
function notifications.step()
	steps = steps + 1
	if steps == FIRST_SYNC_STEP then
		local ok, err = pcall(unhide_base_problems)
		if not ok then debugPrint("[ux_overhaul] unhiding problem notifications failed: ", tostring(err)) end
	end
	if steps >= FIRST_SYNC_STEP and steps % STEPS_BETWEEN_SYNCS == FIRST_SYNC_STEP % STEPS_BETWEEN_SYNCS then
		local ok, err = pcall(sync_own)
		if not ok then debugPrint("[ux_overhaul] notification sync failed: ", tostring(err)) end
	end
end

return notifications
