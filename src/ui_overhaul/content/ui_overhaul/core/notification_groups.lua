--- Grouping for the notification ridge (gui/notifications.lua): notifications of the same kind
-- share one icon. Pure Lua, no engine access.
--
-- An item is { id = notification id, timestamp = game ms, notification = { type, params } }.
-- Items of the same type with the same distinguishing parameter (town rating key, line problem,
-- number or string param) and the same status form a group. Parameters of an unknown shape are not
-- grouped, so different problems never share an icon.
-- @module ui_overhaul.core.notification_groups
local groups = {}

local function scalar(value)
	local kind = type(value)
	return kind == "number" or kind == "string" or kind == "boolean"
end

--- The group key of a notification. `id` makes the key unique when the parameter is unknown.
function groups.key(notification, id)
	local kind = notification and notification.type or "?"
	local unique = kind .. "|#" .. tostring(id)
	local params = notification and notification.params
	if type(params) ~= "table" then
		if params == nil or scalar(params) then return kind .. "|" .. tostring(params) .. "|" end
		return unique
	end
	local param, part = params.param, ""
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
	local status = params.status
	if status ~= nil and not scalar(status) then return unique end
	return kind .. "|" .. part .. "|" .. (status == nil and "" or tostring(status))
end

local function older(a, b)
	if a.timestamp ~= b.timestamp then return (a.timestamp or 0) < (b.timestamp or 0) end
	return a.id < b.id
end

--- Groups `items`. Returns a list of { key, members, oldest }: groups ordered by their oldest
-- member (so an icon keeps its place when newer members arrive), members newest first.
function groups.build(items)
	local sorted = {}
	for i, item in ipairs(items or {}) do sorted[i] = item end
	table.sort(sorted, older)
	local result, by_key = {}, {}
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
function groups.index(group, current)
	for i, member in ipairs(group.members) do
		if member.id == current then return i end
	end
	return 1
end

--- The id of the member after `current` (towards older ones), wrapping to the newest.
function groups.next_id(group, current)
	local count = #group.members
	if count == 0 then return nil end
	local i = groups.index(group, current) % count + 1
	return group.members[i].id
end

--- Ids of all members, newest first.
function groups.ids(group)
	local ids = {}
	for i, member in ipairs(group.members) do ids[i] = member.id end
	return ids
end

return groups
