-- core/vehicle_search.lua: how the Line Manager's vehicle list is narrowed to a search, restored when
-- it is cleared, and when what the search hid still belongs to the list.
local vehicle_search = require("/ui_overhaul/core/vehicle_search.lua")

---@param ... integer
---@return uo.core.vehicle_search.Entry[]
local function entries(...)
	local result = {} ---@type uo.core.vehicle_search.Entry[]
	for i, entity in ipairs({ ... }) do result[i] = { entity = entity } end
	return result
end

---@param list uo.core.vehicle_search.Entry[]
---@return integer[]
local function ids(list)
	local result = {} ---@type integer[]
	for i, entry in ipairs(list) do result[i] = entry.entity end
	return result
end

---@param set table<integer, true>
---@return fun(entity: integer): boolean
local function only(set) return function(entity) return set[entity] == true end end

---@param _entry uo.core.vehicle_search.Entry
---@return boolean
local function always(_entry) return true end

describe("vehicle search", function()
	it("searches only for text that is more than blanks", function()
		assert.is_false(vehicle_search.active(nil))
		assert.is_false(vehicle_search.active(""))
		assert.is_false(vehicle_search.active("   "))
		assert.is_true(vehicle_search.active(" Re 4"))
	end)

	it("matches a vehicle when any of its texts contains the search", function()
		---@param field string
		---@param text string
		---@return boolean
		local function contains(field, text) return field:lower():find(text:lower(), 1, true) ~= nil end
		assert.is_true(vehicle_search.matches("re 450", { "Zug 3", "Re 450 DPZ", "Line 1" }, contains))
		assert.is_true(vehicle_search.matches("line", { "Zug 3", "", "Line 1" }, contains))
		assert.is_false(vehicle_search.matches("bus", { "Zug 3", "Re 450 DPZ", "" }, contains))
	end)

	it("keeps the matching vehicles in the list, with their selection, and hides the rest unselected", function()
		local result = vehicle_search.narrow({ selected = entries(1, 2), unselected = entries(3, 4) }, {},
			only({ [1] = true, [4] = true }))
		assert.are.same({ 1 }, ids(result.selected))
		assert.are.same({ 4 }, ids(result.unselected))
		assert.are.same({ 2, 3 }, ids(result.stash))
		assert.is_false(result.none)
	end)

	it("matches what an earlier search hid again, each vehicle once", function()
		local result = vehicle_search.narrow({ selected = entries(1), unselected = entries(4) }, entries(2, 3, 4),
			only({ [1] = true, [3] = true }))
		assert.are.same({ 1 }, ids(result.selected))
		assert.are.same({ 3 }, ids(result.unselected))
		assert.are.same({ 4, 2 }, ids(result.stash))
	end)

	it("keeps the whole list, none selected, when nothing matches", function()
		local result = vehicle_search.narrow({ selected = entries(1), unselected = entries(2) }, entries(3),
			only({}))
		assert.is_true(result.none)
		assert.are.same({}, ids(result.selected))
		assert.are.same({ 1, 2, 3 }, ids(result.unselected))
		assert.are.same({}, ids(result.stash))
	end)

	it("puts the hidden vehicles back unselected when the search is cleared", function()
		local result = vehicle_search.restore({ selected = entries(1), unselected = entries(4) }, entries(2, 1, 3))
		assert.are.same({ 1 }, ids(result.selected))
		assert.are.same({ 4, 2, 3 }, ids(result.unselected))
	end)

	it("tells a changed selection or an added vehicle from a list that was replaced", function()
		local before = { selected = entries(1), unselected = entries(2) }
		-- the same vehicles, selected differently, one added
		assert.is_true(vehicle_search.continues(before, { selected = entries(1, 2), unselected = entries(5) }, always))
		-- another line's vehicles in its place
		assert.is_false(vehicle_search.continues(before, { selected = entries(5), unselected = {} }, always))
		-- emptied
		assert.is_false(vehicle_search.continues(before, { selected = {}, unselected = {} }, always))
		-- a sold vehicle gone is no replacement
		---@param entry uo.core.vehicle_search.Entry
		---@return boolean
		local function not_two(entry) return entry.entity ~= 2 end
		assert.is_true(vehicle_search.continues(before, { selected = entries(1), unselected = {} }, not_two))
	end)

	it("drops vehicles taken off the list and gone ones from what the search hid", function()
		---@param entry uo.core.vehicle_search.Entry
		---@return boolean
		local function not_five(entry) return entry.entity ~= 5 end
		assert.are.same({ 3 }, ids(vehicle_search.without(entries(2, 3, 5), { 2, 9 }, not_five)))
	end)
end)
