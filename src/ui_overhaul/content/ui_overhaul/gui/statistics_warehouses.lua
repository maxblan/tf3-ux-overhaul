--- Statistics window, "Warehouses" tab, with additions to the vanilla tab:
--   * the Stocks column shows each cargo's icon with its quantity, the largest first (base: icons
--     only, in no particular order); more than four go behind a "+N" whose tooltip lists them all
--   * a cargo drop-down next to the quick filters: picking a cargo lists the warehouses that hold it
--     and sorts the Stocks column by its quantity ("Any cargo": every warehouse, sorted by the total)
--   * quick filters All / Full / Empty and the totals of the rows shown: count, stored of capacity,
--     upkeep
-- A Lua conversion of the base tab (gui/statistics/statistic_warehouses.tl), registered under the
-- base recipe names so the base stylesheet applies, installed through a react-replacement-config
-- (statistics_warehouses.script.lua). If rendering fails, the base tab is shown.
-- @module ui_overhaul.gui.statistics_warehouses
local builtin = require("::/gui/main/builtin.lua")
local cargo_react_util = require("::/gui/main/cargo_react_util.tl")
local cargo_util = require("::/gui/main/cargo_util.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local notification_util = require("::/game_mechanics/notifications/notification_util.tl")
local react = require("::/gui/main/react.lua")
local statistics_react_util = require("::/gui/statistics/statistics_react_util.tl")
local table_util = require("::/scripts/table_util.tl")
local base_warehouses_statistic = require("::/gui/statistics/statistic_warehouses.tl")
local statistics_common = require("/ui_overhaul/gui/statistics_common.lua")

local statistics_warehouses = {}

local styleClassRightAligned = "right-aligned"
local SHOWN_CARGOS = 4 -- icons with quantities that fit the Stocks column
local FULL = 0.9 -- "Full": at least 90 % of the capacity used

-- Quick filter and cargo of the tab; kept for the session.
local QUICK_FILTERS = { all = true, full = true, empty = true }
local quick_filter = "all"
local cargo_filter = -1 -- -1: any cargo

local REFRESH_STEPS = 30

-- Data ---------------------------------------------------------------------------------------------

--- Stored and capacity of a warehouse, and its cargo: { stored, capacity, cargos = { {id, count} }
-- (largest first), takes = { [id] = true } (configured cargo, for an empty warehouse) }.
-- Engine reads only.
function statistics_warehouses.read(entity)
	local configs = cargo_util.calculateStockConfigs(entity)
	local result = { stored = 0, capacity = 0, cargos = {}, takes = {}, all = false }
	for _i, config in ipairs(configs or {}) do
		result.stored = result.stored + (config.stored or 0)
		result.capacity = result.capacity + (config.capacity or 0)
		if config.allCargoTypes then result.all = true end
		for _j, id in ipairs(config.cargoTypesSorted or {}) do
			if api.engine.util.stock.isCargoTypeCurrentlyProduced(id) then result.takes[id] = true end
		end
	end
	for _i, cargo in ipairs(cargo_util.calculateStockCargoCount(entity, false) or {}) do
		if cargo.count and cargo.count > 0 then
			result.cargos[#result.cargos + 1] = { cargo.cargoType, cargo.count }
		end
	end
	statistics_warehouses.sort_cargos(result.cargos)
	return result
end

--- Sorts { {id, count} } largest first, then by cargo id (stable across refreshes).
function statistics_warehouses.sort_cargos(cargos)
	table.sort(cargos, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		return a[1] < b[1]
	end)
	return cargos
end

--- Quantity of cargo `id` in `data` (0 if none).
function statistics_warehouses.count_of(data, id)
	for _i, cargo in ipairs(data.cargos) do
		if cargo[1] == id then return cargo[2] end
	end
	return 0
end

--- Whether a warehouse's data passes the quick filter and the cargo filter.
function statistics_warehouses.passes(data, filter, cargo)
	if filter == "full" and not (data.capacity > 0 and data.stored / data.capacity >= FULL) then return false end
	if filter == "empty" and data.stored > 0 then return false end
	if cargo and cargo >= 0 then return statistics_warehouses.count_of(data, cargo) > 0 end
	return true
end

-- Cells ----------------------------------------------------------------------------------------------

local WarehouseLocationAndNameCell = react.RegisterRecipe("WarehouseLocationAndNameCell", function(params)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			line_react_util.NameTextView{ entity = params.rowKey, locationButton = true, stackEntityOpen = true,
				editMode = true },
		},
	}
end)

local function cargo_name(id)
	return api.res.cargoTypeRep.get(id).name
end

local WarehouseCargoTypesCell = react.RegisterRecipe("WarehouseCargoTypesCell", function(params)
	local entity = params.rowKey
	local state = engine_react_util.useStepStateTimer(function()
		local ok, data = pcall(statistics_warehouses.read, entity)
		return ok and data or nil
	end, 1.0)
	local data = state:old()
	local children = {}
	if data and #data.cargos > 0 then
		local all_lines = {}
		for i, cargo in ipairs(data.cargos) do
			local count = lang_util.formatInt(cargo[2])
			all_lines[#all_lines + 1] = string.format("%s: %s", _(cargo_name(cargo[1])), count)
			if i <= SHOWN_CARGOS then
				children[#children + 1] = cargo_react_util.makeCargoIcon(cargo[1],
					"text-icon-size-hack, cargo-icon-only" .. (i == 1 and ", first" or ""))
				children[#children + 1] = builtin.TextView{
					meta = { class = "font-scale-body, uio-warehouse-count" }, text = count,
				}
			end
		end
		if #data.cargos > SHOWN_CARGOS then
			children[#children + 1] = builtin.TextView{
				meta = { class = "font-scale-body, uio-warehouse-count", tooltip = table.concat(all_lines, "\n") },
				text = "+" .. tostring(#data.cargos - SHOWN_CARGOS),
			}
		end
	elseif data and data.all then
		children[1] = builtin.ImageView{
			meta = { class = "text-icon-size-hack, cargo-icon-only, first", tooltip = _("All Cargo Types") },
			path = cargo_util.getMixedCargoIcon(),
		}
	elseif data then
		-- empty: the cargo it takes, as the base cell shows it
		local ids = {}
		for id in pairs(data.takes) do ids[#ids + 1] = id end
		table.sort(ids)
		for i, id in ipairs(ids) do
			children[#children + 1] = cargo_react_util.makeCargoIcon(id,
				"text-icon-size-hack, cargo-icon-only" .. (i == 1 and ", first" or ""))
		end
	end
	-- the spacer keeps the icons and quantities together on the left
	children[#children + 1] = gui_react_util.makeHorizontalSpacer()
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{
				meta = { class = "cargo-icon-group", forceFocusable = true },
				layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children },
			},
		},
	}
end)

local function number_cell(name, value_fn, format)
	return react.RegisterRecipe(name, function(params)
		local entity = params.rowKey
		local state = engine_react_util.useStepStateTimer(function()
			local ok, value = pcall(value_fn, entity)
			return ok and value or 0
		end)
		react.setStyleClasses(styleClassRightAligned)
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.Component{
					meta = { forceFocusable = true },
					layout = builtin.BoxLayout{
						orientation = builtin.type.Orientation.Horizontal,
						children = { builtin.TextView{ meta = { class = "font-scale-body" }, text = format(state:old()) } },
					},
				},
			},
		}
	end)
end

local function stored_of(entity) return statistics_warehouses.read(entity).stored end
local function capacity_of(entity) return statistics_warehouses.read(entity).capacity end
local function utilization_of(entity)
	local data = statistics_warehouses.read(entity)
	return data.capacity > 0 and data.stored / data.capacity or 0
end
local function upkeep_of(entity) return api.engine.util.maintenance.calcMaintenanceForSubconstruction(entity) end

local WarehouseSupplyCell = number_cell("WarehouseSupplyCell", stored_of, lang_util.formatInt)
local WarehouseDemandCell = number_cell("WarehouseDemandCell", capacity_of, lang_util.formatInt)
local WarehouseCoverageCell = number_cell("WarehouseCoverageCell", utilization_of,
	function(v) return api.util.toStringPercentPrecision(v, 0) end)
local WarehouseUpkeepCell = number_cell("WarehouseUpkeepCell", upkeep_of,
	function(v) return api.util.formatMoney(v) end)

-- Cargo picker ---------------------------------------------------------------------------------------

-- A drop-down list: "Any cargo", then every cargo stored anywhere, by name. (A drop-down entry may
-- only be a text or an image: an icon with a text in a layout crashes the game, observed in game.)
local function cargo_picker(cargo_ids, selected, on_select)
	local function item(value, label)
		return builtin.ComboBoxItem{ value = value,
			content = builtin.TextView{ meta = { class = "font-scale-body" }, text = label } }
	end
	local items = { item("-1", _("Any cargo")) }
	local found = selected < 0
	for _i, id in ipairs(cargo_ids) do
		items[#items + 1] = item(tostring(id), _(cargo_name(id)))
		if id == selected then found = true end
	end
	return builtin.ComboBox{
		meta = { class = "uio-warehouse-cargo-picker", tag = "uio.statistics.warehouses.cargo" },
		value = found and tostring(selected) or "-1",
		items = items,
		onValueChange = function(value) on_select(tonumber(value) or -1) end,
	}
end

-- Tab ------------------------------------------------------------------------------------------------

local function render(params)
	local quickFilterState = react.useState(quick_filter)
	local cargoState = react.useState(cargo_filter)
	local filter, cargo = quickFilterState:old(), cargoState:old()
	local function setQuickFilter(key)
		if not QUICK_FILTERS[key] then return end
		quick_filter = key
		quickFilterState:set(key)
	end
	local function setCargo(id)
		cargo_filter = id
		cargoState:set(id)
	end
	-- lets other mods and the testbench switch the filters
	react.onEvent("uio.statistics.warehouses.filter", function(_e, key) setQuickFilter(key) end)
	react.onEvent("uio.statistics.warehouses.cargo", function(_e, id) setCargo(id or -1) end)

	local function searchMatches(key, data)
		if params.searchString == "" then return true end
		if lang_util.stringContains(api.engine.util.getEntityName(key), params.searchString) then return true end
		for _i, c in ipairs(data.cargos) do
			if lang_util.stringContains(_(cargo_name(c[1])), params.searchString) then return true end
		end
		return false
	end

	local stepsRef = react.useRef(0)
	local signature = filter .. "|" .. tostring(cargo) .. "|" .. statistics_common.filterSignature(params)
	local tableState = engine_react_util.useStepState(function(cur)
		local keys = api.engine.getEntitiesWithComponent(api.type.ComponentType.WAREHOUSE)
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
		local filteredKeysMap, cargoSet, totals = {}, {}, { count = 0, stored = 0, capacity = 0, upkeep = 0 }
		for _i, key in ipairs(keys) do
			if api.engine.entityExists(key)
				and not (params.filterShowOnlyVisible and not api.gui.byEntity.isVisible(key)) then
				local data = statistics_warehouses.read(key)
				for _j, c in ipairs(data.cargos) do cargoSet[c[1]] = true end
				if statistics_warehouses.passes(data, filter, cargo) and searchMatches(key, data) then
					filteredKeysMap[key] = true
					totals.count = totals.count + 1
					totals.stored = totals.stored + data.stored
					totals.capacity = totals.capacity + data.capacity
					totals.upkeep = totals.upkeep + upkeep_of(key)
				end
			end
		end
		local cargoIds = {}
		for id in pairs(cargoSet) do cargoIds[#cargoIds + 1] = id end
		table.sort(cargoIds)
		return {
			keys = same and cur.keys or keys,
			notificationsState = same and cur.notificationsState or notificationsState,
			signature = signature,
			filteredKeysMap = filteredKeysMap,
			cargoIds = cargoIds,
			totals = totals,
		}
	end, nil, function(a, b) return a == b end)

	local function getProblemsCompareValue(entity)
		return statistics_react_util.getProblemsCompareValue(tableState:old().notificationsState or {}, entity)
	end
	-- the picked cargo's quantity, or the total stored
	local function getStockCompareValue(entity)
		local data = statistics_warehouses.read(entity)
		if cargo >= 0 then return statistics_warehouses.count_of(data, cargo) end
		return data.stored
	end

	local columnsDesc = {
		{ name = _("Name"), recipe = WarehouseLocationAndNameCell,
			getCompareValue = function(e) return api.engine.util.getEntityName(e) end, weight = 5 },
		{ path = "::/gui/statistics/icons/alert.tga", tooltip = _("Problems"), recipe = statistics_react_util.ProblemsCell,
			getCompareValue = getProblemsCompareValue, weight = 0.5 },
		{ name = _("Stocks"), recipe = WarehouseCargoTypesCell, getCompareValue = getStockCompareValue, weight = 4 },
		{ name = _("Stored"), recipe = WarehouseSupplyCell, getCompareValue = stored_of,
			headerStyleClass = styleClassRightAligned, weight = 1.5 },
		{ name = _("Capacity"), recipe = WarehouseDemandCell, getCompareValue = capacity_of,
			headerStyleClass = styleClassRightAligned, weight = 1.5 },
		{ name = _("Utilization"), recipe = WarehouseCoverageCell, getCompareValue = utilization_of,
			headerStyleClass = styleClassRightAligned, weight = 1.5 },
		{ name = _("Upkeep"), recipe = WarehouseUpkeepCell, getCompareValue = upkeep_of,
			headerStyleClass = styleClassRightAligned, weight = 2 },
	}
	local columns = {}
	for i, col in ipairs(columnsDesc) do
		columns[i] = builtin.ColumnDesc{ name = col.name, path = col.path, tooltip = col.tooltip, recipe = col.recipe,
			getCompareValue = col.getCompareValue, headerStyleClass = col.headerStyleClass, weight = col.weight }
	end

	local tableRef = react.useNodeRef()
	react.onMount(function()
		params.declareFilterOnMount({}, "Warehouses")
		tableRef:get():focus()
	end)
	react.setPreferredFocusChild(tableRef)

	local totals = tableState:old().totals
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			statistics_common.QuickFilterBar{
				filters = {
					{ key = "all", label = _("All") },
					{ key = "full", label = _("Full") },
					{ key = "empty", label = _("Empty") },
				},
				selected = filter,
				onSelect = setQuickFilter,
				tagPrefix = "uio.statistics.warehouses.filter.",
				totalsId = "uio.statistics.warehouses.totals",
				totalsText = lang_util.format(_("{count} warehouses"), { count = lang_util.formatInt(totals.count) })
					.. ", " .. lang_util.format(_("{stored} of {capacity} stored"),
						{ stored = lang_util.formatInt(totals.stored), capacity = lang_util.formatInt(totals.capacity) }),
				amountLabel = _("Upkeep"),
				amount = totals.upkeep,
				extra = cargo_picker(tableState:old().cargoIds, cargo, setCargo),
			},
			builtin.DataTable(react.ref(tableRef), {
				meta = { id = "menu.statistics.warehouses" },
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
	}
end

local Replacement = react.RegisterRecipe("WarehousesStatistic", function(params)
	local ok, node = pcall(render, params)
	if ok then return node end
	debugPrint("[ui_overhaul] statistics warehouses tab failed, showing the base tab: ", tostring(node))
	return builtin.BoxLayout{ children = { react.CallOriginalRecipe(base_warehouses_statistic, params) } }
end)

--- Called from the react-replacement-config before the UI starts.
function statistics_warehouses.install(replacement_api)
	replacement_api.ReplaceRecipe(base_warehouses_statistic, Replacement)
end

return statistics_warehouses
