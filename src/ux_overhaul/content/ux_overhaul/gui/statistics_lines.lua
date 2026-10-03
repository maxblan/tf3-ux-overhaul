--- Statistics window, "Lines" tab, with three additions to the vanilla tab:
--   * quick filters above the table: All / Losing money / Problems / No vehicles
--   * a totals row under the table: lines, vehicles and balance of the rows shown
--   * fixed sorting: "Vehicles" sorts by vehicle count (base: by model ids), "Balance" sorts by the
--     value it displays (base: by the sum over the line's current vehicles)
-- A Lua conversion of the base tab (gui/statistics/statistic_lines.tl), registered under the base
-- recipe names so the base stylesheet applies, installed through a react-replacement-config
-- (statistics_lines.script.lua). If rendering fails, the base tab is shown.
-- @module ux_overhaul.gui.statistics_lines
local builtin = require("::/gui/main/builtin.lua")
local cargo_react_util = require("::/gui/main/cargo_react_util.tl")
local cargo_util = require("::/gui/main/cargo_util.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local line_util = require("::/gui/line_vehicle_mgmt/line_util.tl")
local notification_util = require("::/game_mechanics/notifications/notification_util.tl")
local react = require("::/gui/main/react.lua")
local statistics_react_util = require("::/gui/statistics/statistics_react_util.tl")
local vehicle_react_util = require("::/gui/line_vehicle_mgmt/vehicle_react_util.tl")
local base_lines_statistic = require("::/gui/statistics/statistic_lines.tl")

local statistics_lines = {}

local styleClassRightAligned = "right-aligned"

-- Quick filter of the tab; kept for the session so reopening the window shows the same rows.
local QUICK_FILTERS = { "all", "losing", "problems", "empty" }
local quick_filter = "all"

local function line_balance(lineEntity)
	local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
	local fromTime = math.max(gameTime - api.util.getDefaultYearDuration(), 0)
	return api.engine.util.finance.calculateBalance({ lineEntity }, fromTime, gameTime, true)
end

local function rightAlignedText(text, tag)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{
				meta = { forceFocusable = true, tag = tag },
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					child = builtin.TextView{ meta = { class = "font-scale-body" }, text = text },
				},
			},
		},
	}
end

-- Cells (1:1 from the base tab) -------------------------------------------------------------------

local LineLocationAndNameCell = react.RegisterRecipe("LineLocationAndNameCell", function(params)
	local entity = params.rowKey
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			line_react_util.ColorWidget{ entity = entity, onClick = nil },
			line_react_util.NameTextView{ entity = entity, locationButton = true, stackEntityOpen = true, editMode = true },
		},
	}
end)

local LineVehiclesCell = react.RegisterRecipe("LineVehiclesCell", function(params)
	local entity = params.rowKey
	local vehiclesState = engine_react_util.useStepState(function()
		return api.engine.system.transportVehicleSystem.getLineVehicles(entity)
	end)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			(#vehiclesState:old() ~= 0) and builtin.Button{
				content = vehicle_react_util.VehicleWidget({ vehicleEntities = vehiclesState:old() }),
				onClick = function()
					react.fireEvent(nil, "openVehicleManager", { openWithLineEntity = entity })
				end,
			} or statistics_react_util.createFocusDummyForGamepad(),
		},
	}
end)

local LineCargoTypesCell = react.RegisterRecipe("LineCargoTypesCell", function(params)
	local entity = params.rowKey
	local cargoTypesState = engine_react_util.useStepStateTimer(function()
		local locationParams = { lineEntity = entity, getTendency = true, showEmpty = true }
		return cargo_util.getSortedProducedCargoTypes(locationParams, "CAPACITY", nil, nil, true)
	end)
	local children = {}
	for _i, cargoTypeId in ipairs(cargoTypesState:old()) do
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
			return statistics_react_util.calculateCargoColumnDataForLine(entity)[field]
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

local LineSupplyCell = cargoColumnCell("LineSupplyCell", "supply", formatCount)
local LineDemandCell = cargoColumnCell("LineDemandCell", "demand", formatCount)
local LineCoverageCell = cargoColumnCell("LineCoverageCell", "coverage", formatPercent)
local LineQualityCell = cargoColumnCell("LineQualityCell", "averageQuality", formatPercent)

local LineFrequencyCell = react.RegisterRecipe("LineFrequencyCell", function(params)
	local entity = params.rowKey
	local frequencyState = engine_react_util.useStepStateTimer(function()
		return line_util.calculateFrequencySeconds(entity)
	end)
	react.setStyleClasses(styleClassRightAligned)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.TextView{
				meta = { class = "font-scale-body", forceFocusable = true },
				text = api.util.formatMinutesSeconds(frequencyState:old()),
			},
		},
	}
end)

local LineRateCell = react.RegisterRecipe("LineRateCell", function(params)
	local entity = params.rowKey
	local rateState = engine_react_util.useStepStateTimer(function()
		return api.engine.util.line.calcLineStationThroughput(entity)
	end)
	react.setStyleClasses(styleClassRightAligned)
	return gui_react_util.integer2TextLayout(rateState:old(), "menu.statistics.line.rateCell")
end)

local LineBalanceCell = react.RegisterRecipe("LineBalanceCell", function(params)
	local entity = params.rowKey
	react.setStyleClasses(styleClassRightAligned)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { line_react_util.LineBalance{ entity = entity, stepTimer = true } },
	}
end)

-- Sort values -----------------------------------------------------------------------------------

local function getLineName(lineEntity)
	return api.engine.util.getEntityName(lineEntity)
end
local function getVehiclesSortValue(lineEntity)
	return #api.engine.system.transportVehicleSystem.getLineVehicles(lineEntity)
end
local function getCargoField(field)
	return function(lineEntity) return statistics_react_util.calculateCargoColumnDataForLine(lineEntity)[field] end
end
local function getRateSortValue(lineEntity)
	return api.engine.util.line.calcLineStationThroughput(lineEntity)
end

-- Quick filters and totals ------------------------------------------------------------------------

local function hasProblems(notificationsState, lineEntity)
	local value = statistics_react_util.getProblemsCompareValue(notificationsState or {}, lineEntity)
	return type(value) == "number" and value > 0
end

local function passesQuickFilter(filter, notificationsState, lineEntity)
	if filter == "losing" then return line_balance(lineEntity) < 0 end
	if filter == "problems" then return hasProblems(notificationsState, lineEntity) end
	if filter == "empty" then return #api.engine.system.transportVehicleSystem.getLineVehicles(lineEntity) == 0 end
	return true
end

local QUICK_FILTER_LABELS = { all = "All", losing = "Losing money", problems = "Problems", empty = "No vehicles" }

--- Quick filters on the left, totals of the rows shown on the right, in one line above the table.
local function QuickFilterBar(selected, onSelect, totals)
	local buttons, selectedIndex = {}, 1
	for i, key in ipairs(QUICK_FILTERS) do
		buttons[i] = { content = builtin.TextView{ meta = { class = "font-scale-body" }, text = _(QUICK_FILTER_LABELS[key]) },
			meta = { tag = "uxo.statistics.filter." .. key } }
		if key == selected then selectedIndex = i end
	end
	local balanceClass = totals.balance < 0 and "font-scale-body, negative" or "font-scale-body, positive"
	return builtin.BoxLayout{
		meta = { class = "uxo-statistics-quick-filters" },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.ToggleButtonGroup{
				buttons = buttons,
				selected = selectedIndex,
				onValueChange = function(index) onSelect(QUICK_FILTERS[index]) end,
			},
			gui_react_util.makeHorizontalSpacer(),
			builtin.TextView{ meta = { class = "font-scale-body", id = "uxo.statistics.totals" },
				text = lang_util.format(_("{lines} lines, {vehicles} vehicles"),
					{ lines = lang_util.formatInt(totals.lines), vehicles = lang_util.formatInt(totals.vehicles) }) },
			builtin.TextView{ meta = { class = "font-scale-body" }, text = _("Balance") },
			builtin.TextView{ meta = { class = balanceClass }, text = api.util.formatMoney(totals.balance) },
		},
	}
end

-- The tab -------------------------------------------------------------------------------------------

local function render(params)
	local categories = {
		{ imageFile = "::/gui/statistics/icons/vehicle_bus_18.tga", tooltip = _("Show Road Lines"), carrier = api.type.enum.Carrier.ROAD },
		{ imageFile = "::/gui/statistics/icons/vehicle_tram_18.tga", tooltip = _("Show Tram Lines"), carrier = api.type.enum.Carrier.TRAM },
		{ imageFile = "::/gui/statistics/icons/vehicle_train_18.tga", tooltip = _("Show Train Lines"), carrier = api.type.enum.Carrier.RAIL },
		{ imageFile = "::/gui/statistics/icons/vehicle_ship_18.tga", tooltip = _("Show Ship Lines"), carrier = api.type.enum.Carrier.WATER },
		{ imageFile = "::/gui/statistics/icons/vehicle_airplane_18.tga", tooltip = _("Show Air Lines"), carrier = api.type.enum.Carrier.AIR },
	}
	local quickFilterState = react.useState(quick_filter)
	local filter = quickFilterState:old()
	-- lets other mods and the testbench switch the quick filter: "uxo.statistics.filter" <key>
	react.onEvent("uxo.statistics.filter", function(_e, key)
		quick_filter = key
		quickFilterState:set(key)
	end)

	-- base filter (carrier, visibility, search) plus the quick filter
	local function filterFn(key, notificationsState)
		if not api.engine.entityExists(key) then return false end
		if params.filterShowOnlyVisible and not api.gui.byEntity.isLineEmptyOrVisible(key) then return false end
		local allowedCarriers = statistics_react_util.getCarrierFilterFromCategories(categories, params.filterShowCategories)
		if allowedCarriers ~= nil and not line_util.filterLine(allowedCarriers, key) then return false end
		if not passesQuickFilter(filter, notificationsState, key) then return false end
		if params.searchString == "" then return true end
		if lang_util.stringContains(api.engine.util.getEntityName(key), params.searchString) then return true end
		for _i, info in ipairs(cargo_util.calculateSortedLineCargoInfo(key)) do
			if lang_util.stringContains(cargo_util.getCargoNameById(info.cargoType), params.searchString) then return true end
		end
		return false
	end

	local function makeFilteredKeys(keys, curVisualizations, notificationsState)
		local visualizations, resultMap = {}, {}
		for _i, key in ipairs(keys) do
			if filterFn(key, notificationsState) then
				local visualization = builtin.type.LineVisualization.new()
				visualization.entity = key
				visualizations[#visualizations + 1] = visualization
				resultMap[key] = true
			end
		end
		local changed = curVisualizations == nil or #visualizations ~= #curVisualizations
		if not changed then
			for i, vis in ipairs(visualizations) do
				if curVisualizations[i].entity ~= vis.entity then
					changed = true
					break
				end
			end
		end
		if not changed then return nil, nil end -- lets statistics.tl compare the table with ==
		return visualizations, resultMap
	end

	local tableState = engine_react_util.useStepState(function(cur)
		local keys = api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
		local notificationsState = notification_util.getPersistingEntity2NotificationFromNative(
			notification_util.externalGetNotificationsStateNative())
		local visualizeLines, filteredKeysMap = makeFilteredKeys(keys, cur and cur.visualizeLines or nil, notificationsState)
		if cur and cur.filter ~= filter then
			-- the quick filter changed: rebuild even if the rows look the same
			visualizeLines, filteredKeysMap = makeFilteredKeys(keys, nil, notificationsState)
		end
		return {
			keys = keys,
			filter = filter,
			notificationsState = notificationsState,
			visualizeLines = visualizeLines or cur.visualizeLines,
			filteredKeysMap = filteredKeysMap or cur.filteredKeysMap,
		}
	end)

	local totalsState = engine_react_util.useStepStateTimer(function()
		local totals = { lines = 0, vehicles = 0, balance = 0 }
		local map = tableState:hasExpired() and {} or tableState:old().filteredKeysMap or {}
		for line in pairs(map) do
			if api.engine.entityExists(line) then
				totals.lines = totals.lines + 1
				totals.vehicles = totals.vehicles + #api.engine.system.transportVehicleSystem.getLineVehicles(line)
				totals.balance = totals.balance + line_balance(line)
			end
		end
		return totals
	end, 1.0)

	local tableRef = react.useNodeRef()
	react.setPreferredFocusChild(tableRef)
	react.onMount(function()
		params.declareFilterOnMount(categories, "Lines")
		tableRef:get():focus()
	end)

	local function getProblemsCompareValue(lineEntity)
		return statistics_react_util.getProblemsCompareValue(tableState:old().notificationsState or {}, lineEntity)
	end

	local columnsDesc = {
		{ name = _("Name"), recipe = LineLocationAndNameCell, getCompareValue = getLineName, weight = 5.44 },
		{ path = "::/gui/statistics/icons/alert.tga", tooltip = _("Problems"), recipe = statistics_react_util.ProblemsCell,
			getCompareValue = getProblemsCompareValue, weight = 0.75 },
		{ name = _("Vehicles"), recipe = LineVehiclesCell, getCompareValue = getVehiclesSortValue, weight = 3.5 },
		{ name = _("Cargo"), recipe = LineCargoTypesCell, getCompareValue = cargo_util.calculateSortedLineCargoInfoCompareValue,
			weight = 2 },
		{ name = pGetText("noun", "Load"), recipe = LineSupplyCell, getCompareValue = getCargoField("supply"), weight = 1.5,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Capacity"), recipe = LineDemandCell, getCompareValue = getCargoField("demand"), weight = 1.6,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Utilization"), recipe = LineCoverageCell, getCompareValue = getCargoField("coverage"), weight = 2,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Satisfaction"), recipe = LineQualityCell, getCompareValue = getCargoField("averageQuality"), weight = 2,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Frequency"), recipe = LineFrequencyCell, getCompareValue = line_util.calculateFrequencySeconds, weight = 1.9,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Rate"), recipe = LineRateCell, getCompareValue = getRateSortValue, weight = 1.5,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Balance"), recipe = LineBalanceCell, getCompareValue = line_balance, weight = 1.6,
			headerStyleClass = styleClassRightAligned },
	}
	local columns = {}
	for i, col in ipairs(columnsDesc) do
		columns[i] = builtin.ColumnDesc{ name = col.name, path = col.path, tooltip = col.tooltip, recipe = col.recipe,
			getCompareValue = col.getCompareValue, headerStyleClass = col.headerStyleClass, weight = col.weight }
	end

	react.provideApi({
		getVisualizeLines = function()
			if tableState:hasExpired() then return nil end
			return tableState:old().visualizeLines
		end,
	})

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			QuickFilterBar(filter, function(key)
				quick_filter = key
				quickFilterState:set(key)
			end, totalsState:old()),
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
							meta = { id = "menu.statistics.lines" },
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

local Replacement = react.RegisterRecipe("LinesStatistic", function(params)
	local ok, node = pcall(render, params)
	if ok then return node end
	debugPrint("[ux_overhaul] statistics lines tab failed, showing the base tab: ", tostring(node))
	return react.CallOriginalRecipe(base_lines_statistic, params)
end)

--- Called from the react-replacement-config before the UI starts.
function statistics_lines.install(replacement_api)
	replacement_api.ReplaceRecipe(base_lines_statistic, Replacement)
end

return statistics_lines
