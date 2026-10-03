--- Status in the Line Manager's rows, where the player already looks (backlog D1):
--   line rows:    cargo icons, vehicle count and the 12-month balance (red when losing money)
--   vehicle rows: age (red once the lifespan is reached)
-- Wraps the exported base recipe line_react_util.ManagerNotificationWidget, which the base renders
-- at the end of every line, depot and vehicle row (react-replacement-config, see lvm_rows.script.lua);
-- the base problem icons stay. Uses the rows' own text style (font-scale-body).
-- @module ui_overhaul.gui.lvm_rows
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local vehicle_util = require("::/gui/line_vehicle_mgmt/vehicle_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local cargo_util = require("::/gui/main/cargo_util.tl")
local cargo_react_util = require("::/gui/main/cargo_react_util.tl")

local lvm_rows = {}

local REFRESH = 2.0 -- seconds; the Line Manager can show many rows
local CARGO_SLOTS = 3 -- icons that fit the fixed-width cargo column (lvm_rows.css.lua)

local function horizontal(children, class)
	return builtin.BoxLayout{ meta = { class = class }, orientation = builtin.type.Orientation.Horizontal,
		children = children }
end

local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

--- Cargo type ids a line carries, passengers first: the capacities of its vehicles, sorted as the
-- line's header in the Line Manager (LineCargoDisplay) sorts them. A line without vehicles falls
-- back to the cargo its stops are configured to load. Engine reads only.
function lvm_rows.cargo_types(line)
	local ids = cargo_util.getSortedProducedCargoTypes(
		{ lineEntity = line, getTendency = true, showEmpty = true }, "CAPACITY", true, nil, true)
	local result = {}
	for i, id in ipairs(ids) do result[i] = id end
	if #result > 0 then return result end

	local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
	local seen = {}
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
function lvm_rows.cargo_slots(ids, slots)
	local shown, more = {}, {}
	local fit = #ids <= slots and slots or slots - 1
	for i, id in ipairs(ids) do
		if i <= fit then shown[#shown + 1] = id else more[#more + 1] = id end
	end
	return shown, more
end

--- Plain data for a row's entity (engine reads only; runs in a timer callback).
local function read(entity)
	if not api.engine.entityExists(entity) then return nil end
	local t = now()
	if api.engine.getComponent(entity, api.type.ComponentType.LINE) then
		local from = math.max(t - api.util.getDefaultYearDuration(), 0)
		return {
			kind = "line",
			vehicles = #api.engine.system.transportVehicleSystem.getLineVehicles(entity),
			balance = api.engine.util.finance.calculateBalance({ entity }, from, t, true),
			cargo = lvm_rows.cargo_types(entity),
		}
	end
	local tv = api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv then
		local purchase_and_lifespan = vehicle_util.getMinPurchaseTimeAndLifespan(tv)
		return { kind = "vehicle", purchase = purchase_and_lifespan[1], lifespan = purchase_and_lifespan[2], now = t }
	end
	return nil
end

local function text(value, class, tooltip)
	return builtin.TextView{ meta = { class = class, tooltip = tooltip }, text = value }
end

--- Fixed-width column of cargo icons (tooltip: the cargo name), so rows with 0 to 3 icons align.
local function cargo_column(entity, ids)
	local shown, more = lvm_rows.cargo_slots(ids, CARGO_SLOTS)
	local children = {}
	for _i, id in ipairs(shown) do
		children[#children + 1] = cargo_react_util.makeCargoIcon(id, "uio-lvm-cargo-icon")
	end
	if #more > 0 then
		local names = {}
		for i, id in ipairs(more) do names[i] = api.res.cargoTypeRep.get(id).name end
		children[#children + 1] = text("+" .. tostring(#more), "font-scale-body, uio-lvm-cargo-more",
			table.concat(names, ", "))
	end
	return builtin.Component{
		meta = { class = "uio-lvm-cargo", id = "uio.lvm.cargo." .. tostring(entity) },
		layout = horizontal(children, "uio-lvm-cargo-icons"),
	}
end

local function render_line(entity, d)
	local money = api.util.getAppConfig().moneyPrefix .. api.util.formatKMB(d.balance)
	local class = d.balance < 0 and "font-scale-body, negative, uio-lvm-money" or "font-scale-body, uio-lvm-money"
	return horizontal({
		cargo_column(entity, d.cargo),
		text(tostring(d.vehicles), "font-scale-body, uio-lvm-count", _("Vehicles")),
		text(money, class,
			string.format("%s: %s", _("Profit or loss in the last 12 months"), api.util.formatMoney(d.balance))),
	}, "uio-lvm-info")
end

local function render_vehicle(d)
	local age = api.engine.util.formatAge(d.purchase, d.now)
	local reached = d.lifespan > 0 and d.now >= d.purchase + d.lifespan
	local tooltip = reached and _("Lifetime Reached") or lang_util.format(_("{total} of Lifetime ({age} Remaining)"), {
		total = api.util.toStringPercentPrecision((d.now - d.purchase) / d.lifespan, 0),
		age = api.engine.util.formatAge(d.now, d.purchase + d.lifespan),
	})
	return horizontal({ text(age, reached and "font-scale-body, negative" or "font-scale-body", tooltip) }, "uio-lvm-info")
end

local function render(entity)
	local state = engine_react_util.useStepStateTimer(function() return read(entity) end, REFRESH)
	local d = state:old()
	if not d then return horizontal{} end
	if d.kind == "line" then return render_line(entity, d) end
	return render_vehicle(d)
end

-- Recipe bodies run later than the call that creates their node, so the body guards itself.
local RowInfo = react.RegisterRecipe("UioLvmRowInfo", function(entity)
	local ok, node = pcall(render, entity)
	if ok then return node end
	debugPrint("[ui_overhaul] Line Manager row info failed: ", tostring(node))
	return horizontal{}
end)

local Replacement = react.RegisterRecipe("ManagerNotificationWidget", function(entity)
	return horizontal{ RowInfo(entity), react.CallOriginalRecipe(line_react_util.ManagerNotificationWidget, entity) }
end)

--- Called from the react-replacement-config before the UI starts.
function lvm_rows.install(replacement_api)
	replacement_api.ReplaceRecipe(line_react_util.ManagerNotificationWidget, Replacement)
end

return lvm_rows
