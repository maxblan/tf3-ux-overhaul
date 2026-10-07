--- Line Manager in two columns (feature lvm_columns): the lines with the selected line's stops below
-- them on the left, the vehicles on the right, the top bar with the search across both; the window
-- twice as wide, as tall as before (lvm_columns.css.lua).
--
-- ManagerWindowContent (manager_window.tl) stacks its four parts (top bar, lines, vehicles, line
-- panel) in a BoxLayout without an orientation. The parts are local recipes of that file, and CSS
-- cannot turn a layout, so neither can be changed from outside. The module field builtin.BoxLayout,
-- which the base looks up when it renders, is wrapped instead (builtin_wraps.lua): while
-- ManagerWindowContent renders (react.getCurrentRecipeName), the one layout there with four children
-- and no orientation gets its children arranged in columns; every other layout, in that recipe and
-- everywhere else, passes unchanged. With a gamepad the Line Manager stays as it is: it moves between
-- its parts in their vertical order. On any error the parts stay stacked and one line is logged.
-- Installed by installer.lua.
-- @module ui_overhaul.gui.lvm_columns
local builtin = require("::/gui/main/builtin.lua")
local react = require("::/gui/main/react.lua")
local builtin_wraps = require("ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")

---@class uo.gui.lvm_columns
local lvm_columns = {}

local RECIPE = "ManagerWindowContent"
local PARTS = 4 -- top bar, lines, vehicles, line panel (manager_window.tl, managerChildren)

local report = guard.reporter("Line Manager columns: ")

--- Whether `p` is the Line Manager's stack of its parts, while ManagerWindowContent renders.
---@param p any what the layout builtin got: its params, or a ref, or anything a mod passes
---@return boolean
function lvm_columns.is_stack(p)
	-- the cheap tests first: every layout of the game passes here
	if type(p) ~= "table" or p.is_react_ref_info or p.is_react_style_info then return false end
	if p.orientation ~= nil or p.meta ~= nil or type(p.children) ~= "table" or #p.children ~= PARTS then return false end
	local ok, name = pcall(react.getCurrentRecipeName)
	return ok and name == RECIPE
end

--- Whether the player uses no gamepad (with one the Line Manager keeps its order). Tested as the base
-- tests it (line_react_util.tl): the mode is Undefined until the first input, which is no gamepad
-- (observed in game, where it stayed Undefined through a whole testbench run).
---@return boolean
local function mouse_input()
	local ok, mouse = pcall(function()
		return api.util.getInputMode() ~= api.type["enum"].InputMode.Gamepad
	end)
	return ok and mouse == true
end

--- The stack's params with its parts in columns: the top bar, then a row of the left column (lines,
-- line panel) and the right one (vehicles). Each column is a component with a class, for its width.
---@param p builtin.BoxLayoutParam the stack's params; its children are the four parts
---@param box fun(p: builtin.BoxLayoutParam): react.TreeNodeId the layout builtin below this wrap
---@return builtin.BoxLayoutParam
function lvm_columns.arrange(p, box)
	local parts = p.children ---@cast parts -nil -- is_stack checked them
	local top, lines, vehicles, panel = parts[1], parts[2], parts[3], parts[4]
	local vertical = builtin.type.Orientation.Vertical
	local left = builtin.Component{
		meta = { class = "uio-lvm-left" },
		layout = box{ orientation = vertical, children = { lines, panel } },
	}
	local right = builtin.Component{
		meta = { class = "uio-lvm-right" },
		layout = box{ orientation = vertical, children = { vehicles } },
	}
	local copy = guard.shallow_copy(p) ---@type builtin.BoxLayoutParam
	copy.orientation = vertical
	copy.children = { top, box{ orientation = builtin.type.Orientation.Horizontal, children = { left, right } } }
	return copy
end

---@param base function builtin.BoxLayout, or another mod's wrap of it
---@return function
function lvm_columns.wrap(base)
	---@param p any the layout's params, or a ref before them
	---@param ... any the rest, passed on unchanged
	---@return react.TreeNodeId
	return function(p, ...)
		if select("#", ...) ~= 0 or not lvm_columns.is_stack(p) or not mouse_input() then return base(p, ...) end
		local ok, arranged = pcall(lvm_columns.arrange, p, base)
		if ok then return base(arranged) end
		report("arrange", arranged)
		return base(p)
	end
end

--- Called by installer.lua before the UI starts.
---@param _replacement_api react.ReplacementApi
function lvm_columns.install(_replacement_api)
	builtin_wraps.wrap("BoxLayout", lvm_columns.wrap)
end

return lvm_columns
