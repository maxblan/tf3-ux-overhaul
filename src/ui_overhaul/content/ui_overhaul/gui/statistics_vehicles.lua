--- Statistics window, "Vehicles" tab, with additions to the vanilla tab:
--   * quick filters above the table: All / Losing money / Problems / Old (lifetime reached)
--   * totals of the rows shown on the right of that line: vehicle count and 12-month balance
--   * fixed sorting: "Age" ascending puts the youngest vehicle first (base: by purchase time, so the
--     oldest came first)
--   * the Age cell turns red once the lifetime is reached, with the lifetime tooltip of the line window
-- A Lua conversion of the base tab (gui/statistics/statistic_vehicles.tl), registered under the base
-- recipe names so the base stylesheet applies, installed through a react-replacement-config
-- (statistics_vehicles.script.lua). If rendering fails, the base tab is shown.
-- @module ui_overhaul.gui.statistics_vehicles
local builtin = require("::/gui/main/builtin.lua")
local cargo_react_util = require("::/gui/main/cargo_react_util.tl")
local cargo_util = require("::/gui/main/cargo_util.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local line_util = require("::/gui/line_vehicle_mgmt/line_util.tl")
local notification_util = require("::/game_mechanics/notifications/notification_util.tl")
local react = require("::/gui/main/react.lua")
local statistics_react_util = require("::/gui/statistics/statistics_react_util.tl")
local table_util = require("::/scripts/table_util.tl")
local vehicle_react_util = require("::/gui/line_vehicle_mgmt/vehicle_react_util.tl")
local vehicle_util = require("::/gui/line_vehicle_mgmt/vehicle_util.tl")
local base_vehicles_statistic = require("::/gui/statistics/statistic_vehicles.tl")
local statistics_common = require("/ui_overhaul/gui/statistics_common.lua")

local statistics_vehicles = {}

local styleClassRightAligned = "right-aligned"

-- Quick filter of the tab; kept for the session so reopening the window shows the same rows.
local QUICK_FILTERS = { all = true, losing = true, problems = true, old = true }
local quick_filter = "all"

-- The filtered rows are refreshed every REFRESH_STEPS steps, and at once when a filter changes.
local REFRESH_STEPS = 30

-- Balances for the "Losing money" filter, the totals and the sort, reused for a second of game time.
local cached_balance = statistics_common.makeBalanceCache()

local function rightAlignedText(text)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{
				meta = { forceFocusable = true },
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					child = builtin.TextView{ meta = { class = "font-scale-body" }, text = text },
				},
			},
		},
	}
end

-- Cells (1:1 from the base tab, except Age) -------------------------------------------------------

local VehicleLocationAndNameCell = react.RegisterRecipe("VehicleLocationAndNameCell", function(params)
	local entity = params.rowKey
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			line_react_util.NameTextView{ entity = entity, locationButton = true, stackEntityOpen = true, editMode = true },
		},
	}
end)

local VehicleImageCell = react.RegisterRecipe("VehicleImageCell", function(params)
	local entity = params.rowKey
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Button{
				content = vehicle_react_util.VehicleWidget({ vehicleEntities = { entity } }),
				onClick = function()
					react.fireEvent(nil, "selectEntity", { entity = entity, stack = true })
				end,
			},
		},
	}
end)

local VehicleLineCell = react.RegisterRecipe("VehicleLineCell", function(params)
	local entity = params.rowKey
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{
				meta = { forceFocusable = true },
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						line_react_util.VehicleInstructionsIcon(entity),
						line_react_util.VehicleInstructionsName(entity, false),
					},
				},
			},
		},
	}
end)

local VehicleCargoTypesCell = react.RegisterRecipe("VehicleCargoTypesCell", function(params)
	local entity = params.rowKey
	local unsetCapacities = cargo_util.getVehicleUnsetCapacities(entity)
	local cargoTypeIdsState = engine_react_util.useStepStateTimer(function()
		local locationParams = {
			vehicleEntity = entity,
			getTendency = true,
			showEmpty = true,
			extraCapacity = unsetCapacities.singleCapacities,
		}
		return cargo_util.getSortedProducedCargoTypes(locationParams, "CAPACITY")
	end)
	local children = {}
	for _i, cargoTypeId in ipairs(cargoTypeIdsState:old()) do
		children[#children + 1] = cargo_react_util.makeCargoIcon(cargoTypeId,
			"text-icon-size-hack, cargo-icon-only" .. ((#children == 0) and ", first" or ""))
	end
	local content
	if #children == 0 then
		content = statistics_react_util.createFocusDummyForGamepad()
	else
		content = builtin.Component{
			meta = { class = "cargo-icon-group", forceFocusable = true },
			layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children },
		}
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = { content } }
end)

local function cargoColumnCell(name, field, formatFn)
	return react.RegisterRecipe(name, function(params)
		local entity = params.rowKey
		local state = engine_react_util.useStepStateTimer(function()
			return statistics_react_util.calculateCargoColumnDataForVehicle(entity)[field]
		end)
		react.setStyleClasses(styleClassRightAligned)
		return rightAlignedText(formatFn(state:old()))
	end)
end

local function formatCount(value)
	return lang_util.format(_("{count}"), { count = lang_util.formatInt(value) })
end
local function formatPercent(value)
	return api.util.toStringPercentPrecision(value, 0)
end

local VehicleCargoSupplyCell = cargoColumnCell("VehicleCargoSupplyCell", "supply", formatCount)
local VehicleCargoDemandCell = cargoColumnCell("VehicleCargoDemandCell", "demand", formatCount)
local VehicleCargoCoverageCell = cargoColumnCell("VehicleCargoCoverageCell", "coverage", formatPercent)
local VehicleCargoDeliveryCell = cargoColumnCell("VehicleCargoDeliveryCell", "averageQuality", formatPercent)

local VehicleConditionCell = react.RegisterRecipe("VehicleConditionCell", function(params)
	local entity = params.rowKey
	local maintenanceState = engine_react_util.useStepStateTimer(function()
		local condition = vehicle_util.getAvgMaintenanceState(entity)
		return condition
	end)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.TextView{
				meta = { class = "font-scale-body", forceFocusable = true },
				text = vehicle_util.getConditionText(maintenanceState:old()),
			},
		},
	}
end)

local VehicleAgeCell = react.RegisterRecipe("VehicleAgeCell", function(params)
	local entity = params.rowKey
	local ageState = engine_react_util.useStepStateTimer(function()
		local info = vehicle_util.getAge(entity)
		return { age = info.age, agePercent = info.agePercent, timeRemaining = info.timeRemaining }
	end)
	local info = ageState:old()
	local reached = info.timeRemaining == nil
	-- the tooltip of the line window's vehicle list (entity_window/line/line_eow.script.tl)
	local tooltip = reached and _("Lifetime Reached") or lang_util.format(_("{total} of Lifetime ({age} Remaining)"), {
		total = api.util.toStringPercentPrecision((info.agePercent or 0) / 100, 0),
		age = info.timeRemaining,
	})
	react.setStyleClasses(styleClassRightAligned)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.TextView{
				meta = { class = reached and "font-scale-body, negative" or "font-scale-body", forceFocusable = true,
					tooltip = tooltip },
				text = info.age,
			},
		},
	}
end)

local VehicleBalanceCell = react.RegisterRecipe("VehicleBalanceCell", function(params)
	local entity = params.rowKey
	react.setStyleClasses(styleClassRightAligned)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { vehicle_react_util.VehicleBalance{ entity = entity, stepTimer = true } },
	}
end)

-- Sort values -----------------------------------------------------------------------------------

local function getLineCompareValue(vehicleEntity)
	local tv = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv.state == api.type.enum.TransportVehicleState.EN_ROUTE or tv.state == api.type.enum.TransportVehicleState.AT_TERMINAL then
		return api.engine.util.getEntityName(tv.line)
	end
	return (tv.state == api.type.enum.TransportVehicleState.GOING_TO_DEPOT) and _("Going to Depot") or _("In Depot")
end
local function getNameCompareValue(vehicleEntity)
	return api.engine.util.getEntityName(vehicleEntity)
end
local function getCargoField(field)
	return function(vehicleEntity) return statistics_react_util.calculateCargoColumnDataForVehicle(vehicleEntity)[field] end
end
local function getConditionCompareValue(vehicleEntity)
	local condition = vehicle_util.getAvgMaintenanceState(vehicleEntity)
	return condition
end
-- the base sorts by purchase time, so ascending showed the oldest first; ascending now means youngest first
local function getAgeCompareValue(vehicleEntity)
	return -vehicle_util.getAge(vehicleEntity).purchaseTime
end

-- Quick filters ---------------------------------------------------------------------------------

local function lifetimeReached(transportVehicle, gameTime)
	local purchaseTimeAndLifespan = vehicle_util.getMinPurchaseTimeAndLifespan(transportVehicle)
	return gameTime >= purchaseTimeAndLifespan[1] + purchaseTimeAndLifespan[2]
end

local function passesQuickFilter(filter, notificationsState, vehicleEntity, transportVehicle, gameTime)
	if filter == "losing" then return cached_balance(vehicleEntity) < 0 end
	if filter == "problems" then return statistics_common.hasProblems(notificationsState, vehicleEntity) end
	if filter == "old" then return lifetimeReached(transportVehicle, gameTime) end
	return true
end

-- The tab -------------------------------------------------------------------------------------------

local function render(params)
	local categories = {
		{ imageFile = "::/gui/statistics/icons/vehicle_bus_18.tga", tooltip = _("Show Road Vehicles"), carrier = api.type.enum.Carrier.ROAD },
		{ imageFile = "::/gui/statistics/icons/vehicle_tram_18.tga", tooltip = _("Show Trams"), carrier = api.type.enum.Carrier.TRAM },
		{ imageFile = "::/gui/statistics/icons/vehicle_train_18.tga", tooltip = _("Show Trains"), carrier = api.type.enum.Carrier.RAIL },
		{ imageFile = "::/gui/statistics/icons/vehicle_ship_18.tga", tooltip = _("Show Ships"), carrier = api.type.enum.Carrier.WATER },
		{ imageFile = "::/gui/statistics/icons/vehicle_airplane_18.tga", tooltip = _("Show Air Vehicles"), carrier = api.type.enum.Carrier.AIR },
	}
	local quickFilterState = react.useState(quick_filter)
	local filter = quickFilterState:old()
	local function setQuickFilter(key)
		if not QUICK_FILTERS[key] then return end
		quick_filter = key
		quickFilterState:set(key)
	end
	-- lets other mods and the testbench switch the quick filter: "uio.statistics.vehicles.filter" <key>
	react.onEvent("uio.statistics.vehicles.filter", function(_e, key) setQuickFilter(key) end)

	-- base filter (visibility, carrier, search; statistic_vehicles.tl fnUserFilter) plus the quick filter
	local function filterFn(key, notificationsState, gameTime)
		if not api.engine.entityExists(key) then return false end
		local transportVehicle = api.engine.getComponent(key, api.type.ComponentType.TRANSPORT_VEHICLE)
		if transportVehicle == nil then return false end
		if params.filterShowOnlyVisible and not api.gui.byEntity.isVehicleVisible(key) then return false end
		local allowedCarriers = statistics_react_util.getCarrierFilterFromCategories(categories, params.filterShowCategories)
		if allowedCarriers ~= nil and not table_util.arrayContains(allowedCarriers, transportVehicle.carrier) then return false end
		if not passesQuickFilter(filter, notificationsState, key, transportVehicle, gameTime) then return false end
		if params.searchString == "" then return true end
		if lang_util.stringContains(api.engine.util.getEntityName(key), params.searchString) then return true end
		if lang_util.stringContains(line_util.getVehicleInstructionName(key), params.searchString) then return true end
		for _i, info in ipairs(cargo_util.calculateSortedVehicleCargoInfo(key)) do
			if lang_util.stringContains(cargo_util.getCargoNameById(info.cargoType), params.searchString) then return true end
		end
		local condition = vehicle_util.getAvgMaintenanceState(key)
		return lang_util.stringContains(vehicle_util.getConditionText(condition), params.searchString)
	end

	local stepsRef = react.useRef(0)
	local signature = filter .. "|" .. statistics_common.filterSignature(params)
	local tableState = engine_react_util.useStepState(function(cur)
		local keys = api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE,
			{ requireOwnedByPlayer = api.engine.util.getPlayer() })
		local notificationsState = notification_util.getPersistingEntity2NotificationFromNative(
			notification_util.externalGetNotificationsStateNative())
		local same = cur ~= nil and statistics_common.sameArray(cur.keys, keys)
			and table_util.deepEquals(cur.notificationsState, notificationsState)
		local steps = stepsRef:get() + 1
		if same and cur.signature == signature and steps < REFRESH_STEPS then
			stepsRef:set(steps)
			return cur
		end
		stepsRef:set(0)
		local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
		local filteredKeysMap = {}
		for _i, key in ipairs(keys) do
			if filterFn(key, notificationsState, gameTime) then filteredKeysMap[key] = true end
		end
		if same and cur.signature == signature and statistics_common.sameSet(cur.filteredKeysMap, filteredKeysMap) then
			return cur
		end
		return {
			keys = same and cur.keys or keys,
			notificationsState = same and cur.notificationsState or notificationsState,
			signature = signature,
			filteredKeysMap = filteredKeysMap,
		}
	end, nil, function(a, b) return a == b end)

	local totalsState = engine_react_util.useStepStateTimer(function()
		local totals = { vehicles = 0, balance = 0 }
		local map = tableState:hasExpired() and {} or tableState:old().filteredKeysMap or {}
		for vehicle in pairs(map) do
			if api.engine.entityExists(vehicle) then
				totals.vehicles = totals.vehicles + 1
				totals.balance = totals.balance + cached_balance(vehicle)
			end
		end
		return totals
	end, 1.0)

	local function getProblemsCompareValue(vehicleEntity)
		return statistics_react_util.getProblemsCompareValue(tableState:old().notificationsState or {}, vehicleEntity)
	end

	local columnsDesc = {
		{ name = _("Name"), recipe = VehicleLocationAndNameCell, getCompareValue = getNameCompareValue, weight = 6.7 },
		{ path = "::/gui/statistics/icons/alert.tga", tooltip = _("Problems"), recipe = statistics_react_util.ProblemsCell,
			getCompareValue = getProblemsCompareValue, weight = 1 },
		{ name = _("Vehicle"), recipe = VehicleImageCell, getCompareValue = vehicle_util.GetVehicleModelIds, weight = 2.8 },
		{ name = _("Line"), recipe = VehicleLineCell, getCompareValue = getLineCompareValue, weight = 5 },
		{ name = _("Cargo"), recipe = VehicleCargoTypesCell,
			getCompareValue = cargo_util.calculateSortedVehicleCargoInfoCompareValue, weight = 2.4 },
		{ name = pGetText("noun", "Load"), recipe = VehicleCargoSupplyCell, getCompareValue = getCargoField("supply"),
			weight = 1.65, headerStyleClass = styleClassRightAligned },
		{ name = _("Capacity"), recipe = VehicleCargoDemandCell, getCompareValue = getCargoField("demand"),
			weight = 2.2, headerStyleClass = styleClassRightAligned },
		{ name = _("Utilization"), recipe = VehicleCargoCoverageCell, getCompareValue = getCargoField("coverage"),
			weight = 2.8, headerStyleClass = styleClassRightAligned },
		{ name = _("Satisfaction"), recipe = VehicleCargoDeliveryCell, getCompareValue = getCargoField("averageQuality"),
			weight = 2.6, headerStyleClass = styleClassRightAligned },
		{ name = _("Condition"), recipe = VehicleConditionCell, getCompareValue = getConditionCompareValue, weight = 3.05 },
		{ name = _("Age"), recipe = VehicleAgeCell, getCompareValue = getAgeCompareValue, weight = 2,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Balance"), recipe = VehicleBalanceCell, getCompareValue = cached_balance, weight = 2.25,
			headerStyleClass = styleClassRightAligned },
	}
	local columns = {}
	for i, col in ipairs(columnsDesc) do
		columns[i] = builtin.ColumnDesc{ name = col.name, path = col.path, tooltip = col.tooltip, recipe = col.recipe,
			getCompareValue = col.getCompareValue, headerStyleClass = col.headerStyleClass, weight = col.weight }
	end

	local tableRef = react.useNodeRef()
	react.setPreferredFocusChild(tableRef)
	react.onMount(function()
		params.declareFilterOnMount(categories, "Vehicles")
		tableRef:get():focus()
	end)

	local totals = totalsState:old()
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			statistics_common.QuickFilterBar{
				filters = {
					{ key = "all", label = _("All") },
					{ key = "losing", label = _("Losing money") },
					{ key = "problems", label = _("Problems") },
					{ key = "old", label = _("Old") },
				},
				selected = filter,
				onSelect = setQuickFilter,
				tagPrefix = "uio.statistics.vehicles.filter.",
				totalsId = "uio.statistics.vehicles.totals",
				totalsText = lang_util.format(_("{count} vehicles"), { count = lang_util.formatInt(totals.vehicles) }),
				amountLabel = _("Balance"),
				amount = totals.balance,
				amountClass = statistics_common.balanceClass(totals.balance),
			},
			builtin.FloatingLayout{
				children = {
					builtin.FloatingLayoutChild{
						overflowMode = builtin.type.FloatingLayoutOverflowMode.Overflow,
						item = builtin.KeybindingHintDisplay{
							meta = { class = "overflow-mode, hint-focus-table" },
							source = params.filterIaComp,
							inputAction = "IA_OPTION2",
						},
					},
					builtin.FloatingLayoutChild{
						item = builtin.DataTable(react.ref(tableRef), {
							meta = { id = "menu.statistics.vehicles" },
							iaSort = "IA_OPTION1",
							columns = columns,
							rowKeys = tableState:old().keys,
							userParam = { deleteLineFeedback = params.deleteLineFeedback,
								notificationState = tableState:old().notificationsState },
							initialSortColumn = params.initialSortColumn,
							onSortColumnChange = params.onSortColumnChange,
							fnUserFilter = function(key) return tableState:old().filteredKeysMap[key] or false end,
						}),
					},
				},
			},
		},
	}
end

local Replacement = react.RegisterRecipe("VehiclesStatistic", function(params)
	local ok, node = pcall(render, params)
	if ok then return node end
	debugPrint("[ui_overhaul] statistics vehicles tab failed, showing the base tab: ", tostring(node))
	return builtin.BoxLayout{ children = { react.CallOriginalRecipe(base_vehicles_statistic, params) } }
end)

--- Called from the react-replacement-config before the UI starts.
function statistics_vehicles.install(replacement_api)
	replacement_api.ReplaceRecipe(base_vehicles_statistic, Replacement)
end

return statistics_vehicles
