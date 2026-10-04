--- Grouping for the notification ridge (gui/notifications.lua): notifications of the same kind
-- share one icon. Pure Lua, no engine access.
--
-- An item is { id = notification id, timestamp = game ms, notification = { type, params } }.
-- Items of the same type with the same distinguishing parameter (town rating key, line problem,
-- number or string param) and the same status form a group. Parameters of an unknown shape are not
-- grouped, so different problems never share an icon.
-- @module ui_overhaul.core.notification_groups
local groups = {}

---@class uo.core.notification_groups.Notification
---@field type string the notification script, e.g. "::/game_mechanics/notifications/types/line_warning.script"
---@field params any each notification type has its own parameters; groups.key reads them defensively

---@class uo.core.notification_groups.Item
---@field id integer notification id
---@field timestamp? number game ms
---@field notification? uo.core.notification_groups.Notification

---@class uo.core.notification_groups.Group
---@field key string
---@field members uo.core.notification_groups.Item[] newest first
---@field oldest? number timestamp of the oldest member
---@field tile? string the icon that shows the group (set by groups.place)

---@class uo.core.notification_groups.Tile
---@field anchor number timestamp of the group's oldest member when the icon appeared
---@field born integer creation number, breaks ties between equal anchors

---@class uo.core.notification_groups.Tiles
---@field by_member table<integer, string> tile of each notification on the ridge
---@field tiles table<string, uo.core.notification_groups.Tile>
---@field count integer tiles created so far, for unique keys

---@param value any
---@return boolean
local function scalar(value)
	local kind = type(value)
	return kind == "number" or kind == "string" or kind == "boolean"
end

--- The group key of a notification. `id` makes the key unique when the parameter is unknown.
---@param notification? uo.core.notification_groups.Notification
---@param id? integer
---@return string
function groups.key(notification, id)
	local kind = notification and notification.type or "?"
	local unique = kind .. "|#" .. tostring(id)
	local params = notification and notification.params
	if type(params) ~= "table" then
		if params == nil or scalar(params) then return kind .. "|" .. tostring(params) .. "|" end
		return unique
	end
	-- any: the parameter's shape depends on the notification type (checked below)
	local param, part = params.param, "" ---@type any, string
	if param == nil then -- luacheck: ignore 542
		-- no distinguishing parameter: group by type
	elseif scalar(param) then
		part = tostring(param)
	elseif type(param) == "table" and scalar(param.key) then
		part = "key=" .. tostring(param.key)
	elseif type(param) == "table" and scalar(param.lineProblem) then
		part = "problem=" .. tostring(param.lineProblem)
	else
		return unique
	end
	-- any: like `param`, the status's shape depends on the notification type
	local status = params.status ---@type any
	if status ~= nil and not scalar(status) then return unique end
	return kind .. "|" .. part .. "|" .. (status == nil and "" or tostring(status))
end

---@param a uo.core.notification_groups.Item
---@param b uo.core.notification_groups.Item
---@return boolean
local function older(a, b)
	if a.timestamp ~= b.timestamp then return (a.timestamp or 0) < (b.timestamp or 0) end
	return a.id < b.id
end

--- Groups `items`. Returns a list of { key, members, oldest }: groups ordered by their oldest
-- member (so an icon keeps its place when newer members arrive), members newest first.
---@param items? uo.core.notification_groups.Item[]
---@return uo.core.notification_groups.Group[]
function groups.build(items)
	local sorted = {} ---@type uo.core.notification_groups.Item[]
	for i, item in ipairs(items or {}) do sorted[i] = item end
	table.sort(sorted, older)
	local result = {} ---@type uo.core.notification_groups.Group[]
	local by_key = {} ---@type table<string, uo.core.notification_groups.Group>
	for _i, item in ipairs(sorted) do
		local key = groups.key(item.notification, item.id)
		local group = by_key[key]
		if not group then
			group = { key = key, members = {}, oldest = item.timestamp }
			by_key[key] = group
			result[#result + 1] = group
		end
		table.insert(group.members, 1, item)
	end
	return result
end

--- Index of the member with id `current` in `group`, or 1 (the newest) if it is not there.
---@param group uo.core.notification_groups.Group
---@param current? integer
---@return integer
function groups.index(group, current)
	for i, member in ipairs(group.members) do
		if member.id == current then return i end
	end
	return 1
end

--- The id of the member after `current` (towards older ones), wrapping to the newest.
---@param group uo.core.notification_groups.Group
---@param current? integer
---@return integer?
function groups.next_id(group, current)
	local count = #group.members
	if count == 0 then return nil end
	local i = groups.index(group, current) % count + 1
	return group.members[i].id
end

--- Ids of all members, newest first.
---@param group uo.core.notification_groups.Group
---@return integer[]
function groups.ids(group)
	local ids = {} ---@type integer[]
	for i, member in ipairs(group.members) do ids[i] = member.id end
	return ids
end

--- Gives each group of `list` (from groups.build) an icon, `group.tile`, and returns the groups in
-- icon order with the state for the next call. The base ridge keys an icon by notification id, so an
-- icon here follows its members, not the group key: it stays the same React node, with its cursor
-- and place, as long as one of its notifications is on the ridge, also when a member's parameters
-- change the group key. The game itself replaces a notification whose parameters change (a new id,
-- notification_util.updatePersistentNotifications), which leaves an icon as in the base. When groups
-- merge, the oldest member's icon stays. An icon keeps the place it got when it appeared, so it does
-- not move past others when its oldest member goes.
---@param list uo.core.notification_groups.Group[]
---@param previous? uo.core.notification_groups.Tiles the state returned by the last call
---@return uo.core.notification_groups.Group[] placed
---@return uo.core.notification_groups.Tiles state
function groups.place(list, previous)
	local before = previous or { by_member = {}, tiles = {}, count = 0 }
	local state = { by_member = {}, tiles = {}, count = before.count } ---@type uo.core.notification_groups.Tiles
	for _i, group in ipairs(list) do
		local tile ---@type string?
		for i = #group.members, 1, -1 do -- oldest first
			local candidate = before.by_member[group.members[i].id]
			if candidate and not state.tiles[candidate] then
				tile = candidate
				break
			end
		end
		if tile then
			state.tiles[tile] = before.tiles[tile]
		else
			state.count = state.count + 1
			tile = "t" .. state.count
			state.tiles[tile] = { anchor = group.oldest or 0, born = state.count }
		end
		group.tile = tile
		for _j, member in ipairs(group.members) do state.by_member[member.id] = tile end
	end
	local placed = {} ---@type uo.core.notification_groups.Group[]
	for i, group in ipairs(list) do placed[i] = group end
	table.sort(placed, function(a, b)
		-- the loop above gave every group a tile
		---@type uo.core.notification_groups.Tile, uo.core.notification_groups.Tile
		local x, y = state.tiles[a.tile], state.tiles[b.tile]
		if x.anchor ~= y.anchor then return x.anchor < y.anchor end
		return x.born < y.born
	end)
	return placed, state
end

--- True while notification `id` is on the ridge (in `state` from groups.place). An icon member that
-- unmounts while its notification is still shown moved to another icon: nothing was resolved.
---@param state? uo.core.notification_groups.Tiles
---@param id integer
---@return boolean
function groups.shown(state, id)
	return state ~= nil and state.by_member[id] ~= nil
end

return groups
