--- Statistics window, "Stations" tab, with additions to the vanilla tab:
--   * quick filters above the table: All / Problems / Crowded / No lines. "All" is the vanilla set
--     (stations with lines); "No lines" lists the player's stations without lines, which the vanilla
--     tab hides, so their upkeep can be found
--   * totals of the rows shown on the right of that line: station count and upkeep
--   * fixed sorting: "Utilization" sorts by the ratio it displays, used / (capacity + waiting hall)
--     (base: by { used, capacity })
-- A Lua conversion of the base tab (gui/statistics/statistic_stations.tl), registered under the base
-- recipe names so the base stylesheet applies, installed through a react-replacement-config
-- (installer.lua). If rendering fails, the base tab is shown for the
-- rest of the session (fallback.lua).
-- @module ui_overhaul.gui.statistics_stations
local builtin = require("::/gui/main/builtin.lua")
local cargo_util = require("::/gui/main/cargo_util.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local entity_util = require("::/scripts/entity_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local notification_util = require("::/game_mechanics/notifications/notification_util.tl")
local react = require("::/gui/main/react.lua")
local statistics_react_util = require("::/gui/statistics/statistics_react_util.tl")
local table_util = require("::/scripts/table_util.tl")
local base_stations_statistic = require("::/gui/statistics/statistic_stations.tl")
local statistics_common = require("/ui_overhaul/gui/statistics_common.lua")
local fallback = require("/ui_overhaul/gui/fallback.lua")

local statistics_stations = {}

---@class uo.statistics_stations.Totals
---@field stations integer
---@field upkeep integer

-- TableState of the base tab, plus the filters it was built with.
---@class uo.statistics_stations.TableState
---@field keys Engine.Entity[]
---@field notificationsState table<Engine.Entity, integer[]>
---@field signature string
---@field filteredKeysMap table<Engine.Entity, boolean>

-- Recipe2ColumnParam of the base tab.
---@class uo.statistics_stations.ColumnParam
---@field name? string
---@field path? string
---@field tooltip? string
---@field headerStyleClass? string
---@field recipe react.Recipe<builtin.TableCellParam>
---@field getCompareValue fun(stationGroupEntity: Engine.Entity): any sort key: number, string or a table of them
---@field weight number

local styleClassRightAligned = "right-aligned"

-- Quick filter of the tab; kept for the session so reopening the window shows the same rows.
---@type table<string, boolean>
local QUICK_FILTERS = { all = true, problems = true, crowded = true, nolines = true }
local quick_filter = "all"

-- The filtered rows are refreshed every REFRESH_STEPS steps, and at once when a filter changes.
local REFRESH_STEPS = 30

-- Cells (1:1 from the base tab) -------------------------------------------------------------------

---@param params builtin.TableCellParam
---@return react.TreeNodeId
local StationLocationAndNameCell = react.RegisterRecipe("StationLocationAndNameCell", function(params)
	local entity = params.rowKey
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			line_react_util.NameTextView{ entity = entity, locationButton = true, stackEntityOpen = true, editMode = true },
		},
	}
end)

-- The town of all the group's stations, -1 if they are in different towns or none, or the group is gone.
---@param entity Engine.Entity station group
---@return Engine.Entity
local function GetTownOfStationGroup(entity)
	local stationGroup = api.engine.getComponent(entity, api.type.ComponentType.STATION_GROUP)
	if not stationGroup or #stationGroup.stations == 0 then return -1 end
	local town = api.engine.system.stationSystem.getTown(stationGroup.stations[1])
	for _i, station in ipairs(stationGroup.stations) do
		if api.engine.system.stationSystem.getTown(station) ~= town then return -1 end
	end
	return town
end

---@param params builtin.TableCellParam
---@return react.TreeNodeId
local StationTownCell = react.RegisterRecipe("StationTownCell", function(params)
	local entity = params.rowKey
	local townState = engine_react_util.useStepState(function()
		return GetTownOfStationGroup(entity)
	end)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			(townState:old() ~= -1) and line_react_util.NameTextView{ entity = townState:old(), locationButton = true }
				or statistics_react_util.createFocusDummyForGamepad(),
		},
	}
end)

---@param params builtin.TableCellParam
---@return react.TreeNodeId
local StationLinesCell = react.RegisterRecipe("StationLinesCell", function(params)
	local entity = params.rowKey
	local linesState = engine_react_util.useStepStateTimer(function()
		return #api.engine.system.lineSystem.getLinesForStationGroup(entity)
	end)
	react.setStyleClasses(styleClassRightAligned)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.TextView{ text = tostring(linesState:old()), meta = { forceFocusable = true, class = "font-scale-body" } },
		},
	}
end)

---@param groupType game.gui.statistics.statistics_react_util.StationGroupType?
---@return string
local function getStationGroupTypeLabel(groupType)
	---@type table<game.gui.statistics.statistics_react_util.StationGroupType, string>
	local labels = { Cargo = _("Cargo"), Passenger = _("Passenger"), Mixed = _("Mixed") }
	if groupType == nil then return _("--") end
	return labels[groupType]
end

---@param params builtin.TableCellParam
---@return react.TreeNodeId
local StationTypeCell = react.RegisterRecipe("StationTypeCell", function(params)
	local entity = params.rowKey
	local cargoState = engine_react_util.useStepStateTimer(function()
		return statistics_react_util.getStationGroupType(entity)
	end)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.TextView{
				meta = { class = "font-scale-body", forceFocusable = true },
				text = getStationGroupTypeLabel(cargoState:old()),
			},
		},
	}
end)

---@param stationGroupEntity Engine.Entity
---@return UtilStation.StationGroupCapacityUsage
local function getStationUsage(stationGroupEntity)
	local usage = api.engine.util.station.calculateStationGroupCargo(stationGroupEntity, -1)
	if usage.capacity == 0 then -- ports and heliports do not have people waiting on the terminals, so look at stops via qualityData instead
		local qualityData = api.engine.util.cargo.getCargoQualityDataAtStationGroup(stationGroupEntity,
			cargo_util.getPassengerCargoTypeId())
		usage.used = qualityData.countTotal
	end
	return usage
end

---@param params builtin.TableCellParam
---@return react.TreeNodeId
local StationCargoCell = react.RegisterRecipe("StationCargoCell", function(params)
	local entity = params.rowKey
	local cargoState = engine_react_util.useStepStateTimer(function()
		local usage = getStationUsage(entity)
		-- copied into a plain table for the state comparison
		return { used = usage.used, capacity = usage.capacity, waitingHallCapacity = usage.waitingHallCapacity }
	end)
	react.setStyleClasses(styleClassRightAligned)
	local usage = cargoState:old()
	local totalCapacity = usage.capacity + usage.waitingHallCapacity
	---@type react.TreeNodeId
	local child
	if usage.used > 0 and totalCapacity > 0 then
		child = builtin.TextView{
			meta = { class = "font-scale-body", forceFocusable = true },
			text = lang_util.format(_("{used}/{capacity}"), {
				used = lang_util.formatInt(usage.used),
				capacity = lang_util.formatInt(totalCapacity),
			}),
		}
	else
		child = statistics_react_util.createFocusDummyForGamepad()
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = { child } }
end)

---@param entity Engine.Entity station group
---@return UtilCargo.CargoQualityData
local function calculateQualityInfo(entity)
	return api.engine.util.cargo.getCargoQualityDataAtStationGroup(entity, cargo_util.getPassengerCargoTypeId())
end

---@param params builtin.TableCellParam
---@return react.TreeNodeId
local StationQualityCell = react.RegisterRecipe("StationQualityCell", function(params)
	local entity = params.rowKey
	local style = engine_react_util.useStepStateTimer(function()
		return calculateQualityInfo(entity)
	end)
	react.setStyleClasses(styleClassRightAligned)
	---@type react.TreeNodeId[]
	local children = { gui_react_util.makeHorizontalSpacer() }
	if style:old().countBad > 0 then
		children[#children + 1] = gui_react_util.EmoteIcon{ satisfaction = "Aloof", forceFocusable = true }
		children[#children + 1] = builtin.TextView{
			meta = { class = "font-scale-body, inferior" .. (style:old().isVeryBad and ", very" or "") },
			text = lang_util.formatInt(style:old().countBad),
		}
	else
		children[#children + 1] = statistics_react_util.createFocusDummyForGamepad()
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end)

---@param params builtin.TableCellParam
---@return react.TreeNodeId
local StationMaintenanceCell = react.RegisterRecipe("StationMaintenanceCell", function(params)
	local entity = params.rowKey
	local maintenanceState = engine_react_util.useStepStateTimer(function()
		return api.engine.util.maintenance.calcMaintenanceForStationGroup(entity)
	end)
	react.setStyleClasses(styleClassRightAligned)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.TextView{
				meta = { class = "font-scale-body", forceFocusable = true },
				text = api.util.formatMoney(maintenanceState:old()),
			},
		},
	}
end)

-- Sort values -----------------------------------------------------------------------------------

---@param stationGroupEntity Engine.Entity
---@return string?
local function getNameCompareValue(stationGroupEntity)
	return api.engine.util.getEntityName(stationGroupEntity)
end
---@param stationGroupEntity Engine.Entity
---@return string
local function getTownCompareValue(stationGroupEntity)
	local town = GetTownOfStationGroup(stationGroupEntity)
	return town and api.engine.util.getEntityName(town) or ""
end
---@type table<game.gui.statistics.statistics_react_util.StationGroupType, integer>
local stationGroupTypeOrder = { Cargo = 1, Passenger = 2, Mixed = 3 }
---@param stationGroupEntity Engine.Entity
---@return integer
local function getTypeCompareValue(stationGroupEntity)
	local groupType = statistics_react_util.getStationGroupType(stationGroupEntity)
	if not groupType then return 0 end
	return stationGroupTypeOrder[groupType]
end
---@param stationGroupEntity Engine.Entity
---@return integer
local function getLinesCompareValue(stationGroupEntity)
	return #api.engine.system.lineSystem.getLinesForStationGroup(stationGroupEntity)
end
-- the ratio the cell displays (base: { used, capacity }, which ignored the waiting hall and the ratio)
---@param stationGroupEntity Engine.Entity
---@return [number, integer]
local function getUtilizationCompareValue(stationGroupEntity)
	local usage = getStationUsage(stationGroupEntity)
	local totalCapacity = usage.capacity + usage.waitingHallCapacity
	if usage.used > 0 and totalCapacity > 0 then return { usage.used / totalCapacity, usage.used } end
	return { 0, 0 }
end
---@param stationGroupEntity Engine.Entity
---@return [boolean, integer]
local function getQualityCompareValue(stationGroupEntity)
	local quality = calculateQualityInfo(stationGroupEntity)
	return { quality.isVeryBad, quality.countBad }
end
---@param stationGroupEntity Engine.Entity
---@return integer
local function getUpkeepCompareValue(stationGroupEntity)
	return api.engine.util.maintenance.calcMaintenanceForStationGroup(stationGroupEntity)
end

-- Quick filters ---------------------------------------------------------------------------------

---@param filter string
---@param notificationsState table<Engine.Entity, integer[]>
---@param stationGroupEntity Engine.Entity
---@return boolean
local function passesQuickFilter(filter, notificationsState, stationGroupEntity)
	if filter == "problems" then return statistics_common.hasProblems(notificationsState, stationGroupEntity) end
	if filter == "crowded" then
		return api.engine.util.station.calculateStationGroupCargo(stationGroupEntity, -1).overflow == true
	end
	return true
end

-- The tab -------------------------------------------------------------------------------------------

---@param params game.gui.statistics.statistics.StatisticsRecipeParams
---@return react.TreeNodeId
local function render(params)
	---@type game.gui.statistics.statistics.StatisticsRecipeParams.Category[]
	local categories = {
		{ imageFile = "::/gui/statistics/icons/vehicle_bus_18.tga", tooltip = _("Show Road Stations"), carrier = api.type.enum.Carrier.ROAD },
		{ imageFile = "::/gui/statistics/icons/vehicle_tram_18.tga", tooltip = _("Show Tram Stations"), carrier = api.type.enum.Carrier.TRAM },
		{ imageFile = "::/gui/statistics/icons/vehicle_train_18.tga", tooltip = _("Show Train Stations"), carrier = api.type.enum.Carrier.RAIL },
		{ imageFile = "::/gui/statistics/icons/vehicle_ship_18.tga", tooltip = _("Show Ship Stations"), carrier = api.type.enum.Carrier.WATER },
		{ imageFile = "::/gui/statistics/icons/vehicle_airplane_18.tga", tooltip = _("Show Air Vehicle Stations"),
			carrier = api.type.enum.Carrier.AIR },
	}
	local quickFilterState = react.useState(quick_filter)
	local filter = quickFilterState:old()
	---@param key string
	local function setQuickFilter(key)
		if not QUICK_FILTERS[key] then return end
		quick_filter = key
		quickFilterState:set(key)
	end
	-- lets other mods and the testbench switch the quick filter: "uio.statistics.stations.filter" <key>
	react.onEvent("uio.statistics.stations.filter", function(_e, key) setQuickFilter(key) end)

	-- base filter (visibility, carrier, search; statistic_stations.tl fnUserFilter) plus the quick filter
	---@param key Engine.Entity
	---@param notificationsState table<Engine.Entity, integer[]>
	---@return boolean
	local function filterFn(key, notificationsState)
		if not api.engine.entityExists(key) then return false end
		if params.filterShowOnlyVisible and not api.gui.byEntity.isVisible(key) then return false end
		local allowedCarriers = statistics_react_util.getCarrierFilterFromCategories(categories, params.filterShowCategories)
		if allowedCarriers ~= nil then
			local stationCarriers = api.engine.system.stationGroupSystem.getCarriers(key, -1, -1)[1]
			local allowed = false
			for _i, carrier in ipairs(allowedCarriers) do
				if table_util.arrayContains(stationCarriers, carrier) then
					allowed = true
					break
				end
			end
			if not allowed then return false end
		end
		if not passesQuickFilter(filter, notificationsState, key) then return false end
		if params.searchString == "" then return true end
		if lang_util.stringContains(api.engine.util.getEntityName(key) or "", params.searchString) then return true end
		if lang_util.stringContains(api.engine.util.getEntityName(GetTownOfStationGroup(key)) or "",
			params.searchString) then
			return true
		end
		return lang_util.stringContains(getStationGroupTypeLabel(statistics_react_util.getStationGroupType(key)),
			params.searchString)
	end

	local stepsRef = react.useRef(0)
	local signature = filter .. "|" .. statistics_common.filterSignature(params)
	---@param cur uo.statistics_stations.TableState?
	---@return uo.statistics_stations.TableState
	local tableState = engine_react_util.useStepState(function(cur)
		-- vanilla set: station groups with lines; "No lines": the player's station groups without lines
		local wantLines = filter ~= "nolines"
		---@type Engine.Entity[]
		local keys = {}
		api.engine.forEachEntityWithComponent(function(entity)
			local lines = api.engine.system.lineSystem.getLinesForStationGroup(entity)
			if wantLines then
				if entity_util.isOwnedByPlayerOrNotOwned(entity) and #lines > 0 then keys[#keys + 1] = entity end
			elseif #lines == 0 and entity_util.isOwnedByPlayer(entity) then
				keys[#keys + 1] = entity
			end
		end, api.type.ComponentType.STATION_GROUP)
		local notificationsState = notification_util.getPersistingEntity2NotificationFromNative(
			notification_util.externalGetNotificationsStateNative())
		local same = cur ~= nil and statistics_common.sameArray(cur.keys, keys)
			and table_util.deepEquals(cur.notificationsState, notificationsState)
		---@cast cur -nil -- read below only where same is true, which needs a cur
		local steps = stepsRef:get() + 1
		if same and cur.signature == signature and steps < REFRESH_STEPS then
			stepsRef:set(steps)
			return cur
		end
		stepsRef:set(0)
		---@type table<Engine.Entity, boolean>
		local filteredKeysMap = {}
		for _i, key in ipairs(keys) do
			if filterFn(key, notificationsState) then filteredKeysMap[key] = true end
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
		---@type uo.statistics_stations.Totals
		local totals = { stations = 0, upkeep = 0 }
		local map = tableState:hasExpired() and {} or tableState:old().filteredKeysMap or {}
		for stationGroup in pairs(map) do
			if api.engine.entityExists(stationGroup) then
				totals.stations = totals.stations + 1
				totals.upkeep = totals.upkeep + api.engine.util.maintenance.calcMaintenanceForStationGroup(stationGroup)
			end
		end
		return totals
	end, 1.0)

	---@param stationGroupEntity Engine.Entity
	---@return [integer, integer[]]
	local function getProblemsCompareValue(stationGroupEntity)
		return statistics_react_util.getProblemsCompareValue(tableState:old().notificationsState or {}, stationGroupEntity)
	end

	---@type uo.statistics_stations.ColumnParam[]
	local columnsDesc = {
		{ name = _("Name"), recipe = StationLocationAndNameCell, getCompareValue = getNameCompareValue, weight = 4.9 },
		{ path = "::/gui/statistics/icons/alert.tga", tooltip = _("Problems"), recipe = statistics_react_util.ProblemsCell,
			getCompareValue = getProblemsCompareValue, weight = 0.75 },
		{ name = _("Town"), recipe = StationTownCell, getCompareValue = getTownCompareValue, weight = 4 },
		{ name = _("Lines"), recipe = StationLinesCell, getCompareValue = getLinesCompareValue, weight = 1.4,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Type"), recipe = StationTypeCell, getCompareValue = getTypeCompareValue, weight = 1.7 },
		{ name = _("Utilization"), recipe = StationCargoCell, getCompareValue = getUtilizationCompareValue, weight = 2,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Delay"), recipe = StationQualityCell, getCompareValue = getQualityCompareValue, weight = 2,
			headerStyleClass = styleClassRightAligned },
		{ name = _("Upkeep"), recipe = StationMaintenanceCell, getCompareValue = getUpkeepCompareValue, weight = 3,
			headerStyleClass = styleClassRightAligned },
	}
	---@type react.TreeNodeId[]
	local columns = {}
	for i, col in ipairs(columnsDesc) do
		columns[i] = builtin.ColumnDesc{ name = col.name, path = col.path, tooltip = col.tooltip, recipe = col.recipe,
			getCompareValue = col.getCompareValue, headerStyleClass = col.headerStyleClass, weight = col.weight }
	end

	local tableRef = react.useNodeRef()
	react.onMount(function()
		params.declareFilterOnMount(categories, "Stations")
		tableRef:get():focus()
	end)
	react.setPreferredFocusChild(tableRef)

	local totals = totalsState:old()
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			statistics_common.QuickFilterBar{
				filters = {
					{ key = "all", label = _("All") },
					{ key = "problems", label = _("Problems") },
					{ key = "crowded", label = _("Crowded") },
					{ key = "nolines", label = _("No lines") },
				},
				selected = filter,
				onSelect = setQuickFilter,
				tagPrefix = "uio.statistics.stations.filter.",
				totalsId = "uio.statistics.stations.totals",
				totalsText = lang_util.format(_("{count} stations"), { count = lang_util.formatInt(totals.stations) }),
				amountLabel = _("Upkeep"),
				amount = totals.upkeep,
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
							meta = { id = "menu.statistics.stations" },
							iaSort = "IA_OPTION1",
							columns = columns,
							rowKeys = tableState:old().keys,
							userParam = { deleteLineFeedback = params.deleteLineFeedback,
								notificationState = tableState:old().notificationsState },
							initialSortColumn = params.initialSortColumn,
							onSortColumnChange = params.onSortColumnChange,
							---@param key Engine.Entity
							---@return boolean
							fnUserFilter = function(key) return tableState:old().filteredKeysMap[key] or false end,
						}),
					},
				},
			},
		},
	}
end

statistics_stations.switch = fallback.switch("statistics stations tab")
-- The tab node keeps the base tab's focus child.
local Replacement = fallback.replacement(statistics_stations.switch, "StationsStatistic", render,
	base_stations_statistic, { focus = true })

--- Called by installer.lua before the UI starts.
---@param replacement_api react.ReplacementApi
function statistics_stations.install(replacement_api)
	replacement_api.ReplaceRecipe(base_stations_statistic, Replacement)
end

return statistics_stations
