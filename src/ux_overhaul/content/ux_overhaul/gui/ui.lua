--- Small building blocks for the mod's recipes. Every recipe must return a layout as its root
-- (a Component/TextView/Button root aborts the whole game UI), so recipes wrap their content with
-- ui.row / ui.column. GUI thread only.
-- @module ux_overhaul.gui.ui
local builtin = require("::/gui/main/builtin.lua")

local ui = {}

ui.ICONS = {
	alert = "::/gui/statistics/icons/alert.tga",
	lines = "::/gui/game_bar/icons/statistics_line.tga",
	old = "::/gui/line_vehicle_mgmt/icons/condition_bad.tga",
	money = "::/gui/context_helper/icons/menu_finances.tga",
	manage = "::/gui/context_helper/icons/menu_management.tga",
	save = "::/gui/camera_tool/icons/save.tga",
	add = "::/gui/line_vehicle_mgmt/icons/add.tga",
	remove = "::/gui/line_vehicle_mgmt/icons/minus.tga",
	locate = "::/gui/statistics/icons/symbol_eye_18.tga",
	carrier = {
		ROAD = "::/gui/statistics/icons/vehicle_bus_18.tga",
		TRAM = "::/gui/statistics/icons/vehicle_tram_18.tga",
		RAIL = "::/gui/statistics/icons/vehicle_train_18.tga",
		WATER = "::/gui/statistics/icons/vehicle_ship_18.tga",
		AIR = "::/gui/statistics/icons/vehicle_airplane_18.tga",
	},
}

function ui.row(children, meta)
	return builtin.BoxLayout{ meta = meta, orientation = builtin.type.Orientation.Horizontal, children = children }
end

function ui.column(children, meta)
	return builtin.BoxLayout{ meta = meta, orientation = builtin.type.Orientation.Vertical, children = children }
end

--- Text with optional css classes ("positive", "negative", "font-scale-headline" ...) and tooltip.
function ui.text(text, class, tooltip, id)
	return builtin.TextView{ meta = { class = class, tooltip = tooltip, id = id }, text = tostring(text) }
end

function ui.icon(path, tooltip)
	return builtin.ImageView{ meta = { tooltip = tooltip }, path = path }
end

--- Button with any content nodes; `opts` = { tooltip, class, id, enabled = true }.
function ui.button(children, on_click, opts)
	opts = opts or {}
	return builtin.Button{
		meta = { tooltip = opts.tooltip, class = opts.class, id = opts.id, enabled = opts.enabled },
		content = ui.row(children),
		onClick = on_click,
	}
end

--- Joins css classes, skipping nils: ui.classes("a", nil, "b") -> "a, b".
function ui.classes(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local class = select(i, ...)
		if class then parts[#parts + 1] = class end
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

--- Headline font when `selected`, for the active tab or filter button.
function ui.selected(selected)
	return selected and "font-scale-headline" or nil
end

--- css class for a money value: red below zero, green above.
function ui.sign_class(value)
	if value == nil then return nil end
	if value < 0 then return "negative" end
	if value > 0 then return "positive" end
	return nil
end

return ui
