--- Status in the Line Manager's rows, where the player already looks:
--   line rows:    cargo icons, vehicle count and the 12-month balance (red when losing money)
--   vehicle rows: load (in % of the capacity), a condition icon and the age (red once the lifespan
--                 is reached); the row's tooltip names the next stop, speed, load, condition and
--                 delivery quality (vehicle_info.lua)
-- Wraps the exported base recipe line_react_util.ManagerNotificationWidget, which the base renders
-- at the end of every line, depot and vehicle row (react-replacement-config, see installer.lua);
-- the base problem icons stay. Uses the rows' own text style (font-scale-body).
-- @module ui_overhaul.gui.lvm_rows
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local vehicle_util = require("::/gui/line_vehicle_mgmt/vehicle_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local cargo_react_util = require("::/gui/main/cargo_react_util.tl")
local vehicle_info = require("/ui_overhaul/gui/vehicle_info.lua")
local line_cargo = require("/ui_overhaul/gui/line_cargo.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")

-- The base recipe as the module holds it while this mod loads, and safe calls of it (guard.base).
local base_widget = line_react_util.ManagerNotificationWidget
local original_widget = guard.base("ManagerNotificationWidget", base_widget)

---@class uo.gui.lvm_rows
local lvm_rows = {}

local REFRESH = 2.0 -- seconds; the Line Manager can show many rows
local CARGO_SLOTS = 3 -- icons that fit the fixed-width cargo column (lvm_rows.css.lua)

---What `read` found for a line row.
---@class uo.gui.lvm_rows.LineData
---@field kind "line"
---@field vehicles integer
---@field balance integer the last 12 months
---@field cargo CargoTypeId[]

---What `read` found for a vehicle row.
---@class uo.gui.lvm_rows.VehicleData
---@field kind "vehicle"
---@field purchase integer game time (ms)
---@field lifespan integer ms
---@field now integer game time (ms)
---@field info? uo.gui.vehicle_info.Info

---@alias uo.gui.lvm_rows.Data uo.gui.lvm_rows.LineData|uo.gui.lvm_rows.VehicleData

---@param children react.TreeNodeId[]
---@param class? string
---@return react.TreeNodeId
local function horizontal(children, class)
	return builtin.BoxLayout{ meta = { class = class }, orientation = builtin.type.Orientation.Horizontal,
		children = children }
end

---@return integer
local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

--- Whether a vehicle's lifespan is reached and, if not, the share of it used so far. Like the base
-- vehicle table's age cell (line_eow.script.tl LineTableCellAge), a model without a lifespan
-- (lifespan 0, some modded models) counts as reached, so nothing is divided by it.
---@param purchase integer game time of purchase (ms)
---@param lifespan integer ms; 0 for a model without one
---@param t integer game time now (ms)
---@return boolean reached
---@return number|nil fraction of the lifespan used, nil once reached
function lvm_rows.lifetime(purchase, lifespan, t)
	if lifespan <= 0 or t >= purchase + lifespan then return true, nil end
	return false, (t - purchase) / lifespan
end

--- Plain data for a row's entity (engine reads only; runs in a timer callback).
---@param entity Engine.Entity
---@return uo.gui.lvm_rows.Data?
local function read(entity)
	if not api.engine.entityExists(entity) then return nil end
	local t = now()
	if api.engine.getComponent(entity, api.type.ComponentType.LINE) then
		local from = math.max(t - api.util.getDefaultYearDuration(), 0)
		return {
			kind = "line",
			vehicles = #api.engine.system.transportVehicleSystem.getLineVehicles(entity),
			balance = api.engine.util.finance.calculateBalance({ entity }, from, t, true),
			cargo = line_cargo.cargo_types(entity),
		}
	end
	local tv = api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv then
		local purchase_and_lifespan = vehicle_util.getMinPurchaseTimeAndLifespan(tv)
		local ok, info = pcall(vehicle_info.read, entity)
		return { kind = "vehicle", purchase = purchase_and_lifespan[1], lifespan = purchase_and_lifespan[2], now = t,
			info = ok and info or nil }
	end
	return nil
end

---@param value string
---@param class string
---@param tooltip? string
---@return react.TreeNodeId
local function text(value, class, tooltip)
	return builtin.TextView{ meta = { class = class, tooltip = tooltip }, text = value }
end

--- Fixed-width column of cargo icons (tooltip: the cargo name), so rows with 0 to 3 icons align.
---@param entity Engine.Entity
---@param ids CargoTypeId[]
---@return react.TreeNodeId
local function cargo_column(entity, ids)
	local shown, more = line_cargo.cargo_slots(ids, CARGO_SLOTS)
	local children = {} ---@type react.TreeNodeId[]
	for _i, id in ipairs(shown) do
		children[#children + 1] = cargo_react_util.makeCargoIcon(id, "uio-lvm-cargo-icon")
	end
	if #more > 0 then
		local names = {} ---@type string[]
		for i, id in ipairs(more) do names[i] = api.res.cargoTypeRep.get(id).name end
		children[#children + 1] = text("+" .. tostring(#more), "font-scale-body, uio-lvm-cargo-more",
			table.concat(names, ", "))
	end
	return builtin.Component{
		meta = { class = "uio-lvm-cargo", id = "uio.lvm.cargo." .. tostring(entity) },
		layout = horizontal(children, "uio-lvm-cargo-icons"),
	}
end

---@param entity Engine.Entity
---@param d uo.gui.lvm_rows.LineData
---@return react.TreeNodeId
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

---@param d uo.gui.lvm_rows.VehicleData
---@return react.TreeNodeId
local function render_vehicle(d)
	local age = api.engine.util.formatAge(d.purchase, d.now)
	local reached, used = lvm_rows.lifetime(d.purchase, d.lifespan, d.now)
	-- `used` is nil exactly when the lifespan is reached
	local tooltip = used and lang_util.format(_("{total} of Lifetime ({age} Remaining)"), {
		total = api.util.toStringPercentPrecision(used, 0),
		age = api.engine.util.formatAge(d.now, d.purchase + d.lifespan),
	}) or _("Lifetime Reached")
	local children = {} ---@type react.TreeNodeId[]
	local info = d.info
	if info then
		local status = vehicle_info.tooltip(info, false)
		local fraction = vehicle_info.load_fraction(info)
		children[#children + 1] = text(fraction and api.util.toStringPercentPrecision(fraction, 0) or "",
			"font-scale-body, uio-lvm-load", status)
		if info.condition then
			children[#children + 1] = builtin.ImageView{
				meta = { class = "uio-lvm-condition", tooltip = status },
				path = vehicle_util.getConditionIcon(info.condition),
				scaling = builtin.type.ImageViewScaling.AutoFit,
			}
		end
	end
	children[#children + 1] = text(age, reached and "font-scale-body, negative" or "font-scale-body", tooltip)
	return horizontal(children, "uio-lvm-info")
end

---@param entity Engine.Entity
---@return react.TreeNodeId
local function render(entity)
	-- The callback runs inside the hook on the first render: an error there would leave the hook half
	-- declared, so it is caught and the hook is the same on every render.
	local state = engine_react_util.useStepStateTimer(function()
		local ok, d = pcall(read, entity)
		return ok and d or nil
	end, REFRESH)
	local d = state:old()
	if not d then return horizontal{} end
	if d.kind == "line" then return render_line(entity, d) end
	return render_vehicle(d)
end

-- Recipe bodies run later than the call that creates their node, so the body guards itself.
---@param entity Engine.Entity
---@return react.TreeNodeId
local RowInfo = react.RegisterRecipe("UioLvmRowInfo", function(entity)
	local ok, node = pcall(render, entity)
	if ok then return node end
	debugPrint("[ui_overhaul] Line Manager row info failed: ", tostring(node))
	return horizontal{}
end)

---@param entity Engine.Entity
---@return react.TreeNodeId
local Replacement = react.RegisterRecipe("ManagerNotificationWidget", function(entity)
	return horizontal{ RowInfo(entity), original_widget.node(entity) }
end)

--- Called by installer.lua before the UI starts.
---@param replacement_api react.ReplacementApi
function lvm_rows.install(replacement_api)
	replacement_api.ReplaceRecipe(base_widget, Replacement)
end

return lvm_rows
