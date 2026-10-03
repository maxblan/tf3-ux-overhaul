--- Status in the Line Manager's rows, where the player already looks (backlog D1):
--   line rows:    vehicle count and the 12-month balance (red when losing money)
--   vehicle rows: age (red once the lifespan is reached)
-- Wraps the exported base recipe line_react_util.ManagerNotificationWidget, which the base renders
-- at the end of every line, depot and vehicle row (react-replacement-config, see lvm_rows.script.lua);
-- the base problem icons stay. Uses the rows' own text style (font-scale-body).
-- @module ux_overhaul.gui.lvm_rows
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local vehicle_util = require("::/gui/line_vehicle_mgmt/vehicle_util.tl")
local lang_util = require("::/scripts/lang_util.tl")

local lvm_rows = {}

local REFRESH = 2.0 -- seconds; the Line Manager can show many rows

local function horizontal(children, class)
	return builtin.BoxLayout{ meta = { class = class }, orientation = builtin.type.Orientation.Horizontal,
		children = children }
end

local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
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

local function render_line(d)
	local money = api.util.getAppConfig().moneyPrefix .. api.util.formatKMB(d.balance)
	local class = d.balance < 0 and "font-scale-body, negative, uxo-lvm-money" or "font-scale-body, uxo-lvm-money"
	return horizontal({
		text(tostring(d.vehicles), "font-scale-body, uxo-lvm-count", _("Vehicles")),
		text(money, class,
			string.format("%s: %s", _("Profit or loss in the last 12 months"), api.util.formatMoney(d.balance))),
	}, "uxo-lvm-info")
end

local function render_vehicle(d)
	local age = api.engine.util.formatAge(d.purchase, d.now)
	local reached = d.lifespan > 0 and d.now >= d.purchase + d.lifespan
	local tooltip = reached and _("Lifetime Reached") or lang_util.format(_("{total} of Lifetime ({age} Remaining)"), {
		total = api.util.toStringPercentPrecision((d.now - d.purchase) / d.lifespan, 0),
		age = api.engine.util.formatAge(d.now, d.purchase + d.lifespan),
	})
	return horizontal({ text(age, reached and "font-scale-body, negative" or "font-scale-body", tooltip) }, "uxo-lvm-info")
end

local function render(entity)
	local state = engine_react_util.useStepStateTimer(function() return read(entity) end, REFRESH)
	local d = state:old()
	if not d then return horizontal{} end
	if d.kind == "line" then return render_line(d) end
	return render_vehicle(d)
end

-- Recipe bodies run later than the call that creates their node, so the body guards itself.
local RowInfo = react.RegisterRecipe("UxoLvmRowInfo", function(entity)
	local ok, node = pcall(render, entity)
	if ok then return node end
	debugPrint("[ux_overhaul] Line Manager row info failed: ", tostring(node))
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
