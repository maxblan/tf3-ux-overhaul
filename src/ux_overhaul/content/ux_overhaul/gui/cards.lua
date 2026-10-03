--- Entity-window cards (backlog B1, B2, B5): the status the player needs in the window they are
-- looking at, with the fix right next to it.
--   line window:    stops with waiting passengers and cargo, vehicles with -/+, load, frequency
--   station window: lines served with frequency, vehicles and waiting counts per line
--   vehicle window: age, condition and labelled quick actions
-- Rendered by the guarded stubs in cards.script.lua. Data functions run in timer callbacks and only
-- read the engine (no GUI-thread-only calls, no translation); rendering translates.
-- @module ux_overhaul.gui.cards
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local content_card = require("::/gui/main/content_card.tl")
local cargo_util = require("::/gui/main/cargo_util.tl")
local line_util = require("::/gui/line_vehicle_mgmt/line_util.tl")
local vehicle_store_util = require("::/gui/line_vehicle_mgmt/vehicle_store_util.tl")
local format = require("/ux_overhaul/core/format.lua")
local actions = require("/ux_overhaul/gui/actions.lua")
local ui = require("/ux_overhaul/gui/ui.lua")

local cards = {}

local REFRESH = 1.0 -- seconds

local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

local function balance_12_months(entity)
	local t = now()
	local from = math.max(t - api.util.getDefaultYearDuration(), 0)
	return api.engine.util.finance.calculateBalance({ entity }, from, t, true)
end

local function utilization(line)
	local used, capacity = 0, 0
	for _k, usage in pairs(api.engine.util.line.getLineCapacityUsages(line, false) or {}) do
		used, capacity = used + (usage.used or 0), capacity + (usage.capacity or 0)
	end
	return capacity > 0 and used / capacity or nil
end

local function frequency_seconds(line)
	local max_frequency = api.engine.util.line.getMaxFrequency(line)
	if max_frequency < 0.0001 then return 0 end
	return math.floor(1.0 / max_frequency)
end

--- Waiting passengers and cargo at stop `index` (1-based) of `line`; cargo per type name.
local function waiting_at_stop(line, index)
	local passenger_id = api.res.cargoTypeRep.getPassengerCargoTypeId()
	local passengers = api.engine.util.cargo.getCargoQualityDataAtStop(line, index - 1, passenger_id).countTotal or 0
	local cargo, cargo_by_type = 0, {}
	for _i, cargo_id in ipairs(cargo_util.getConfiguredStopCargoTypes({ lineEntity = line, stopIndex1 = index }, true)) do
		if cargo_id ~= passenger_id then
			local count = api.engine.util.cargo.getCargoQualityDataAtStop(line, index - 1, cargo_id).countTotal or 0
			if count > 0 then
				cargo = cargo + count
				cargo_by_type[#cargo_by_type + 1] = { name = api.res.cargoTypeRep.get(cargo_id).name, count = count }
			end
		end
	end
	return passengers, cargo, cargo_by_type
end

local function cargo_tooltip(cargo_by_type)
	local parts = {}
	for _i, entry in ipairs(cargo_by_type) do parts[#parts + 1] = string.format("%s: %d", _(entry.name), entry.count) end
	return #parts > 0 and table.concat(parts, "\n") or nil
end

local function vehicle_buttons(line)
	return {
		ui.button({ ui.icon(ui.ICONS.remove) }, function() actions.remove_vehicle(line) end,
			{ tooltip = _("Send the oldest vehicle to a depot and sell it there") }),
		ui.button({ ui.icon(ui.ICONS.add) }, function() actions.add_vehicle(line) end,
			{ tooltip = _("Buy one more vehicle like the newest one of this line") }),
	}
end

-- Line window (B1) ------------------------------------------------------------------------------

local function line_data(line)
	if not api.engine.entityExists(line) then return nil end
	local data = {
		vehicles = #api.engine.system.transportVehicleSystem.getLineVehicles(line),
		utilization = utilization(line),
		frequency = frequency_seconds(line),
		balance = balance_12_months(line),
		stops = {},
	}
	local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
	for index, stop in ipairs(component and component.stops or {}) do
		local passengers, cargo, cargo_by_type = waiting_at_stop(line, index)
		data.stops[index] = {
			station_group = stop.stationGroup,
			name = api.engine.util.getEntityName(stop.stationGroup) or "",
			passengers = passengers,
			cargo = cargo,
			cargo_by_type = cargo_by_type,
		}
	end
	return data
end

local LineOverview = react.RegisterRecipe("UxoLineOverview", function(params)
	local line = params.line
	local state = engine_react_util.useStepStateTimer(function() return line_data(line) end, REFRESH)
	local d = state:old()
	if not d then return ui.column({}) end
	local frequency = d.frequency > 0 and api.util.formatMinutesSeconds(d.frequency) or "--"
	local rows = {
		ui.row({
			ui.text(string.format(_("%d vehicles"), d.vehicles), "font-scale-headline", nil, "uxo.card.line.vehicles"),
			ui.row(vehicle_buttons(line)),
			ui.text(string.format(_("Load %s"), format.percent(d.utilization)), nil,
				_("Share of the capacity currently in use")),
			ui.text(string.format(_("Every %s"), frequency), nil, _("Interval between vehicles")),
			ui.text(api.util.formatMoney(d.balance), ui.sign_class(d.balance), _("Profit or loss in the last 12 months")),
			ui.button({ ui.icon(ui.ICONS.manage) }, function() actions.open_line_manager(line) end,
				{ tooltip = _("Open in the Line Manager") }),
		}),
	}
	for index, stop in ipairs(d.stops) do
		rows[#rows + 1] = ui.row({
			ui.text(string.format("%d.", index), "uxo-col-severity"),
			ui.button({ ui.text(stop.name, "uxo-col-name") }, function() actions.open_entity(stop.station_group) end,
				{ tooltip = _("Open the station") }),
			ui.text(string.format(_("%d waiting"), stop.passengers), stop.passengers > 0 and "uxo-col-number" or
				"uxo-col-number", _("Passengers waiting for this line")),
			stop.cargo > 0 and ui.text(string.format(_("%d cargo"), stop.cargo), "uxo-col-number",
				cargo_tooltip(stop.cargo_by_type)) or ui.text("", "uxo-col-number"),
		}, { localKey = tostring(index) })
	end
	return ui.column(rows)
end)

function cards.line(params)
	if params.ownershipState ~= "Player" then return ui.row({}) end
	return builtin.BoxLayout{ children = {
		content_card.ContentCard{
			meta = { localKey = "uxoLineOverview" },
			title = _("Overview"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(LineOverview, { line = params.entityId }),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		},
	} }
end

-- Station window (B2) ---------------------------------------------------------------------------

local function station_data(station_group)
	if not api.engine.entityExists(station_group) then return nil end
	local player = api.engine.util.getPlayer()
	local lines = {}
	for _i, entry in ipairs(api.engine.system.lineSystem.getLineStops(station_group)) do
		local line, stop_index0 = entry[1], entry[2]
		local owner = api.engine.getComponent(line, api.type.ComponentType.PLAYER_OWNED)
		if owner ~= nil and owner.player == player then -- like the station window: the player's lines only
			local passengers, cargo, cargo_by_type = waiting_at_stop(line, stop_index0 + 1)
			lines[#lines + 1] = {
				line = line,
				name = api.engine.util.getEntityName(line) or "",
				vehicles = #api.engine.system.transportVehicleSystem.getLineVehicles(line),
				frequency = frequency_seconds(line),
				passengers = passengers,
				cargo = cargo,
				cargo_by_type = cargo_by_type,
			}
		end
	end
	table.sort(lines, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.line < b.line
	end)
	local usage = api.engine.util.station.calculateStationGroupCargo(station_group, -1)
	return {
		lines = lines,
		used = usage.used,
		capacity = usage.capacity + usage.waitingHallCapacity,
		overflow = usage.overflow,
	}
end

local StationOverview = react.RegisterRecipe("UxoStationOverview", function(params)
	local station_group = params.station_group
	local state = engine_react_util.useStepStateTimer(function() return station_data(station_group) end, REFRESH)
	local d = state:old()
	if not d then return ui.column({}) end
	local header = {
		ui.text(string.format(_("%d lines stop here"), #d.lines), ui.classes("font-scale-headline",
			#d.lines == 0 and "negative" or nil), #d.lines == 0 and _("The station only costs upkeep.") or nil,
			"uxo.card.station.lines"),
	}
	if d.capacity > 0 then
		header[#header + 1] = ui.text(string.format(_("%d / %d waiting"), d.used, d.capacity),
			ui.classes("font-scale-headline", d.overflow and "negative" or nil),
			d.overflow and _("The station is overcrowded: add vehicles or platforms") or nil)
	end
	local rows = { ui.row(header) }
	for _i, entry in ipairs(d.lines) do
		local frequency = entry.frequency > 0 and api.util.formatMinutesSeconds(entry.frequency) or "--"
		rows[#rows + 1] = ui.row({
			ui.button({ ui.text(entry.name, "uxo-col-name") }, function() actions.open_entity(entry.line) end,
				{ tooltip = _("Open the line") }),
			ui.text(string.format(_("%d vehicles"), entry.vehicles), "uxo-col-number"),
			ui.text(frequency, "uxo-col-number", _("Interval between vehicles")),
			ui.text(string.format(_("%d waiting"), entry.passengers), "uxo-col-number",
				_("Passengers waiting for this line")),
			entry.cargo > 0 and ui.text(string.format(_("%d cargo"), entry.cargo), "uxo-col-number",
				cargo_tooltip(entry.cargo_by_type)) or ui.text("", "uxo-col-number"),
			ui.row(vehicle_buttons(entry.line)),
		}, { localKey = tostring(entry.line) })
	end
	return ui.column(rows)
end)

function cards.station(params)
	if params.ownershipState == "Foreign" then return ui.row({}) end
	return builtin.BoxLayout{ children = {
		content_card.ContentCard{
			meta = { localKey = "uxoStationOverview" },
			title = _("Lines"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(StationOverview, { station_group = params.entityId }),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		},
	} }
end

-- Vehicle window (B5) ---------------------------------------------------------------------------

local function vehicle_data(vehicle)
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	if not tv then return nil end
	local states = api.type.enum.TransportVehicleState
	local purchase, lifespan
	local condition, parts = 0, 0
	for _i, part in ipairs(tv.transportVehicleConfig.vehicles) do
		local part_lifespan = (api.res.modelRep.get(part.part.modelId).metadata.maintenance or {}).lifespan
		if purchase == nil or part.purchaseTime < purchase then
			purchase, lifespan = part.purchaseTime, part_lifespan and part_lifespan * 1000 or nil
		end
		condition, parts = condition + part.maintenanceState, parts + 1
	end
	local year = api.util.getDefaultYearDuration()
	local on_line = tv.state == states.EN_ROUTE or tv.state == states.AT_TERMINAL
	return {
		line = on_line and tv.line or nil,
		line_name = on_line and api.engine.util.getEntityName(tv.line) or nil,
		age_years = purchase and (now() - purchase) / year or nil,
		lifespan_years = lifespan and lifespan > 0 and lifespan / year or nil,
		condition = parts > 0 and condition / parts or nil,
		to_depot = tv.state == states.GOING_TO_DEPOT or tv.state == states.IN_DEPOT,
		sell_on_arrival = tv.sellOnArrival == true,
		balance = balance_12_months(vehicle),
	}
end

local function replace(vehicle)
	local modes = line_util.getLineAndVehicleCompatibleTransportModesAndCarrier({ vehicle })
	react.fireEvent(nil, "replaceVehicles", {
		vehicleEntities = { vehicle },
		carrier = modes.carrier,
		transportModes = modes.transportModes,
		filterTags = vehicle_store_util.getVehicleFilterTags({ vehicle }),
		openedFromEOW = true,
		onClose = function() end,
	})
end

local VehicleOverview = react.RegisterRecipe("UxoVehicleOverview", function(params)
	local vehicle = params.vehicle
	local state = engine_react_util.useStepStateTimer(function() return vehicle_data(vehicle) end, REFRESH)
	local confirm_sell = react.useState(false)
	local d = state:old()
	if not d then return ui.column({}) end
	local age = d.age_years and string.format(_("%.0f years old"), d.age_years) or ""
	local lifespan = d.lifespan_years
		and string.format(_("%s of lifespan"), format.percent(d.age_years / d.lifespan_years)) or ""
	local old = d.lifespan_years and d.age_years >= d.lifespan_years
	local status = {
		ui.text(age, nil, nil, "uxo.card.vehicle.age"),
		ui.text(lifespan, old and "negative" or nil),
		ui.text(string.format(_("Condition %s"), format.percent(d.condition))),
		ui.text(api.util.formatMoney(d.balance), ui.sign_class(d.balance), _("Profit or loss in the last 12 months")),
	}
	local buttons = {}
	if d.line then
		buttons[#buttons + 1] = ui.button({ ui.text(d.line_name or _("Line")) }, function() actions.open_entity(d.line) end,
			{ tooltip = _("Open the line of this vehicle") })
		buttons[#buttons + 1] = ui.button({ ui.icon(ui.ICONS.add), ui.text(_("Clone")) },
			function() actions.clone_vehicle(vehicle) end, { tooltip = _("Buy an identical vehicle for the same line") })
	end
	buttons[#buttons + 1] = ui.button({ ui.text(_("Replace")) }, function() replace(vehicle) end,
		{ tooltip = _("Choose a new model for this vehicle") })
	if d.sell_on_arrival then
		buttons[#buttons + 1] = ui.text(_("Will be sold in the depot"), "negative")
	elseif not d.to_depot then
		buttons[#buttons + 1] = ui.button({ ui.text(confirm_sell:old() and _("Click again to confirm") or _("Retire")) },
			function()
				if confirm_sell:old() then
					actions.retire_vehicle(vehicle)
					confirm_sell:set(false)
				else
					confirm_sell:set(true)
				end
			end, { tooltip = _("Send to a depot and sell it there"), class = confirm_sell:old() and "negative" or nil })
	end
	return ui.column({ ui.row(status), ui.row(buttons) })
end)

function cards.vehicle(params)
	if params.ownershipState ~= "Player" then return ui.row({}) end
	return builtin.BoxLayout{ children = {
		content_card.ContentCard{
			meta = { localKey = "uxoVehicleOverview" },
			title = _("At a glance"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(VehicleOverview, { vehicle = params.entityId }),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		},
	} }
end

return cards
