--- Addition inside the vanilla line window, built from the game's own widgets and styles: a "Stops"
-- card listing every stop with its waiting passengers (cargo in the tooltip) and a button for the
-- stop's terminals (the Line Manager's popover, terminals.lua), in the same table as the
-- vanilla vehicle list (DataTable, class "line-vehicles-table", NameTextView cells). The base line
-- window shows no stops at all; the station window already lists waiting counts per terminal.
-- Rendered by the guarded stubs in cards.script.lua. State functions run in timer callbacks and only
-- read the engine; rendering translates.
-- @module ui_overhaul.gui.cards
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local content_card = require("::/gui/main/content_card.tl")
local cargo_util = require("::/gui/main/cargo_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")
-- optional: without it the stops have no terminal button
local terminals = guard.module("ui_overhaul_1::/ui_overhaul/gui/terminals.lua")

local cards = {}

local REFRESH = 1.0 -- seconds

local function horizontal(children)
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end

--- Waiting passengers and cargo at stop `index` (1-based) of `line`; cargo as { {name, count} }.
local function waiting_at_stop(line, index)
	local passenger_id = api.res.cargoTypeRep.getPassengerCargoTypeId()
	local passengers = api.engine.util.cargo.getCargoQualityDataAtStop(line, index - 1, passenger_id).countTotal or 0
	local cargo = {}
	for _i, cargo_id in ipairs(cargo_util.getConfiguredStopCargoTypes({ lineEntity = line, stopIndex1 = index }, true)) do
		if cargo_id ~= passenger_id then
			local count = api.engine.util.cargo.getCargoQualityDataAtStop(line, index - 1, cargo_id).countTotal or 0
			if count > 0 then cargo[#cargo + 1] = { name = api.res.cargoTypeRep.get(cargo_id).name, count = count } end
		end
	end
	return passengers, cargo
end

--- A waiting cell: passengers plus cargo, the split per cargo type in the tooltip.
local function waiting_cell(passengers, cargo)
	local total = passengers
	local lines = { string.format("%s: %d", _("Passengers"), passengers) }
	for _i, entry in ipairs(cargo) do
		total = total + entry.count
		lines[#lines + 1] = string.format("%s: %d", _(entry.name), entry.count)
	end
	return horizontal{
		builtin.TextView{ meta = { class = "font-scale-body", tooltip = table.concat(lines, "\n") }, text = tostring(total) },
	}
end

local function card(local_key, title, recipe, param, params)
	return builtin.BoxLayout{ children = {
		content_card.ContentCard{
			meta = { localKey = local_key },
			title = title,
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(recipe, param),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		},
	} }
end

-- Line window: stops -----------------------------------------------------------------------------

local UioStopCell = react.RegisterRecipe("UioStopCell", function(params)
	local line = params.userParam.line
	local state = engine_react_util.useStepStateTimer(function()
		local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
		local stop = component and component.stops[params.rowKey]
		return stop and stop.stationGroup or nil
	end, REFRESH)
	local station_group = state:old()
	if not station_group then return horizontal{} end
	return horizontal{
		builtin.TextView{ meta = { class = "font-scale-body, uio-stop-index" }, text = string.format("%d.", params.rowKey) },
		line_react_util.NameTextView{
			entity = station_group, locationButton = true, stackEntityOpen = true, editMode = false,
		},
		gui_react_util.makeHorizontalSpacer(), -- keeps name and pin left-aligned like the vehicle table
		terminals and terminals.TerminalButton{
			line = line, stopIndex0 = params.rowKey - 1,
			id = "uio.terminals.stops." .. tostring(line) .. "." .. tostring(params.rowKey - 1),
		} or nil,
	}
end)

local UioStopWaitingCell = react.RegisterRecipe("UioStopWaitingCell", function(params)
	local line = params.userParam.line
	local state = engine_react_util.useStepStateTimer(function()
		if not api.engine.entityExists(line) then return nil end
		local passengers, cargo = waiting_at_stop(line, params.rowKey)
		return { passengers = passengers, cargo = cargo }
	end, REFRESH)
	local d = state:old()
	if not d then return horizontal{} end
	return waiting_cell(d.passengers, d.cargo)
end)

local UioStopsTable = react.RegisterRecipe("UioStopsTable", function(params)
	local line = params.line
	local state = engine_react_util.useStepStateTimer(function()
		local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
		local keys = {}
		for index = 1, component and #component.stops or 0 do keys[index] = index end
		return keys
	end, REFRESH)
	return horizontal{
		builtin.DataTable{
			-- The id must be unique: with side-by-side windows two line windows can be open, and a
			-- duplicate id is a React error ("stolen component id", observed in-game).
			meta = { class = "line-vehicles-table", id = "uio.card.line.stops." .. tostring(line) },
			columns = {
				builtin.ColumnDesc{ name = _("Station"), recipe = UioStopCell, weight = 1,
					getCompareValue = function(index) return index end },
				builtin.ColumnDesc{ name = _("Waiting"), recipe = UioStopWaitingCell, headerStyleClass = "age",
					getCompareValue = function(index) return index end },
			},
			rowKeys = state:old(),
			userParam = { line = line },
		},
	}
end)

function cards.line(params)
	if params.ownershipState ~= "Player" then return horizontal{} end
	return card("uioLineStops", _("Stops"), UioStopsTable, { line = params.entityId }, params)
end

return cards
