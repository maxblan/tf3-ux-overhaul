--- Small building blocks for the mod's recipes. Every recipe must return a layout as its root
-- (a Component/TextView/Button root aborts the whole game UI), so recipes wrap their content with
-- ui.row. GUI thread only.
-- @module ui_overhaul.gui.ui
local builtin = require("::/gui/main/builtin.lua")

---@class uo.gui.ui
local ui = {}

ui.ICONS = {
	alert = "::/gui/statistics/icons/alert.tga",
}

---@param children react.TreeNodeId[]
---@param meta? react.Meta
---@return react.TreeNodeId
function ui.row(children, meta)
	return builtin.BoxLayout{ meta = meta, orientation = builtin.type.Orientation.Horizontal, children = children }
end

return ui
