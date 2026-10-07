--- What a line carries, as the Line Manager shows it: the cargo types of a line and how many of their
-- icons fit a column. Shared by the Line Manager's line rows (lvm_rows.lua) and the industry window's
-- Served by card (industry_cards.lua). Engine reads only.
-- @module ui_overhaul.gui.line_cargo
local cargo_util = require("::/gui/main/cargo_util.tl")

---@class uo.gui.line_cargo
local line_cargo = {}

--- Cargo type ids a line carries, passengers first: the capacities of its vehicles, sorted as the
-- line's header in the Line Manager (LineCargoDisplay) sorts them. A line without vehicles falls
-- back to the cargo its stops are configured to load.
---@param line Engine.Entity
---@return CargoTypeId[]
function line_cargo.cargo_types(line)
	local ids = cargo_util.getSortedProducedCargoTypes(
		{ lineEntity = line, getTendency = true, showEmpty = true }, "CAPACITY", true, nil, true)
	local result = {} ---@type CargoTypeId[]
	for i, id in ipairs(ids) do result[i] = id end
	if #result > 0 then return result end

	local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
	local seen = {} ---@type table<CargoTypeId, boolean>
	for _i, stop in ipairs(component and component.stops or {}) do
		for index, load in ipairs(stop.stopConfig.load) do
			local id = index - 1 -- an id vector: index - 1 is the cargo type id
			if load and not seen[id] and api.engine.util.stock.isCargoTypeCurrentlyProduced(id) then
				seen[id] = true
				result[#result + 1] = id
			end
		end
	end
	table.sort(result)
	local passengers = cargo_util.getPassengerCargoTypeId()
	if seen[passengers] then
		for i, id in ipairs(result) do
			if id == passengers then table.remove(result, i) break end
		end
		table.insert(result, 1, passengers)
	end
	return result
end

--- Splits cargo ids into the icons shown and the rest behind a "+N". When they do not all fit,
-- the last slot holds the "+N".
---@param ids CargoTypeId[]
---@param slots integer
---@return CargoTypeId[] shown
---@return CargoTypeId[] more
function line_cargo.cargo_slots(ids, slots)
	local shown, more = {}, {} ---@type CargoTypeId[], CargoTypeId[]
	local fit = #ids <= slots and slots or slots - 1
	for i, id in ipairs(ids) do
		if i <= fit then shown[#shown + 1] = id else more[#more + 1] = id end
	end
	return shown, more
end

return line_cargo
