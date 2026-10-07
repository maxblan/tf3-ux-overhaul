--- The Line Manager's vehicle search on plain lists (gui/lvm_search.lua reads and writes the Line
-- Manager). Pure Lua.
--
-- A search narrows the Line Manager's vehicle list to the vehicles that match. The others leave the
-- list and wait in a stash, so the list's own "select all", its counts and every action reach exactly
-- what is shown; a vehicle hidden this way loses its selection. Clearing the search puts the stash
-- back into the list, unselected. When nothing matches, the list keeps all its vehicles, none
-- selected, and shows no row: emptying it would close the list, and the search field with it.
-- @module ui_overhaul.core.vehicle_search
local vehicle_search = {}

---An entry of the Line Manager's vehicle list (entity_util.EntityAndRevision; only `entity` is read).
---@class uo.core.vehicle_search.Entry
---@field entity integer

---The two halves of the Line Manager's vehicle list.
---@class uo.core.vehicle_search.Lists
---@field selected uo.core.vehicle_search.Entry[]
---@field unselected uo.core.vehicle_search.Entry[]

---What `narrow` makes of a list.
---@class uo.core.vehicle_search.Narrowed: uo.core.vehicle_search.Lists
---@field stash uo.core.vehicle_search.Entry[] the vehicles hidden from the list
---@field none boolean nothing matches: the list keeps all vehicles, none selected, and shows no row

--- Whether `text` searches for something (anything but blanks).
---@param text? string
---@return boolean
function vehicle_search.active(text)
	return type(text) == "string" and text:find("%S") ~= nil
end

--- Whether any of `fields` contains `text`, by `contains` (the game's test, which ignores case).
---@param text string
---@param fields string[]
---@param contains fun(field: string, text: string): boolean
---@return boolean
function vehicle_search.matches(text, fields, contains)
	for _i, field in ipairs(fields) do
		if field ~= "" and contains(field, text) then return true end
	end
	return false
end

---@param entries uo.core.vehicle_search.Entry[]
---@return table<integer, true>
local function entities_of(entries)
	local result = {} ---@type table<integer, true>
	for _i, entry in ipairs(entries) do result[entry.entity] = true end
	return result
end

--- `list` and the entries of `more` that are not in `list` or in `skip`, each vehicle once.
---@param list uo.core.vehicle_search.Entry[]
---@param more uo.core.vehicle_search.Entry[]
---@param skip? table<integer, true>
---@return uo.core.vehicle_search.Entry[]
local function joined(list, more, skip)
	local result, seen = {}, {} ---@type uo.core.vehicle_search.Entry[], table<integer, true>
	for _i, part in ipairs({ list, more }) do
		for _j, entry in ipairs(part) do
			if not seen[entry.entity] and not (skip and skip[entry.entity]) then
				seen[entry.entity] = true
				result[#result + 1] = entry
			end
		end
	end
	return result
end

--- The list narrowed to the vehicles `match` accepts. `stash` holds what an earlier search of the same
-- list hid; it is matched again, as a vehicle that comes back unselected.
---@param lists uo.core.vehicle_search.Lists
---@param stash uo.core.vehicle_search.Entry[]
---@param match fun(entity: integer): boolean
---@return uo.core.vehicle_search.Narrowed
function vehicle_search.narrow(lists, stash, match)
	local selected = joined(lists.selected, {})
	local unselected = joined(lists.unselected, stash, entities_of(selected))
	local result = { selected = {}, unselected = {}, stash = {}, none = false } ---@type uo.core.vehicle_search.Narrowed
	for _i, entry in ipairs(selected) do
		if match(entry.entity) then
			result.selected[#result.selected + 1] = entry
		else
			result.stash[#result.stash + 1] = entry
		end
	end
	for _i, entry in ipairs(unselected) do
		if match(entry.entity) then
			result.unselected[#result.unselected + 1] = entry
		else
			result.stash[#result.stash + 1] = entry
		end
	end
	if #result.selected + #result.unselected > 0 then return result end
	return { selected = {}, unselected = joined(selected, unselected), stash = {}, none = true }
end

--- The list with the stash back in it, unselected: the search is cleared.
---@param lists uo.core.vehicle_search.Lists
---@param stash uo.core.vehicle_search.Entry[]
---@return uo.core.vehicle_search.Lists
function vehicle_search.restore(lists, stash)
	local selected = joined(lists.selected, {})
	return { selected = selected, unselected = joined(lists.unselected, stash, entities_of(selected)) }
end

--- Whether the list `now` goes on from the list `before`: every vehicle of `before` that is still
-- `alive` is in `now`. So it is a change of the selection, vehicles added or sold ones gone, and what
-- the search hid from `before` belongs to `now` too; otherwise the list was replaced or cut down.
---@param before uo.core.vehicle_search.Lists
---@param now uo.core.vehicle_search.Lists
---@param alive fun(entry: uo.core.vehicle_search.Entry): boolean
---@return boolean
function vehicle_search.continues(before, now, alive)
	local present = entities_of(joined(now.selected, now.unselected))
	for _i, part in ipairs({ before.selected, before.unselected }) do
		for _j, entry in ipairs(part) do
			if not present[entry.entity] and alive(entry) then return false end
		end
	end
	return true
end

--- The stash without the vehicles in `entities` (taken off the list) and without those not `alive`.
---@param stash uo.core.vehicle_search.Entry[]
---@param entities integer[]
---@param alive fun(entry: uo.core.vehicle_search.Entry): boolean
---@return uo.core.vehicle_search.Entry[]
function vehicle_search.without(stash, entities, alive)
	local gone = {} ---@type table<integer, true>
	for _i, entity in ipairs(entities) do gone[entity] = true end
	local result = {} ---@type uo.core.vehicle_search.Entry[]
	for _i, entry in ipairs(stash) do
		if not gone[entry.entity] and alive(entry) then result[#result + 1] = entry end
	end
	return result
end

return vehicle_search
