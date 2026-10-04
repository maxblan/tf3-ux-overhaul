---@meta

---A style rule's properties, as .css.lua files write them, the ones this repo uses.
---@class game.gui.main.stylesheetutil.Style
---@field size? (number|string)[] { width, height }, -1: unset; a string is relative to the screen, e.g. "70vh"
---@field minSize? (number|string)[]
---@field maxSize? (number|string)[]
---@field padding? number[] { top, right, bottom, left }
---@field margin? number[] { top, right, bottom, left }
---@field gravity? number[] { x, y } in [0, 1]
---@field innerSpacing? number[]
---@field textAlignment? number[]
---@field anchorPoint? number[]
---@field color? number[] { r, g, b[, a] }
---@field borderColor? number[]
---@field backgroundColor? number[]
---@field backgroundColor1? number[]
---@field alphaScale? number
---@field fontWeight? string
---@field visibility? string

---Adds a rule for `selector` (comma-separated selectors allowed) to the stylesheet list.
---@alias game.gui.main.stylesheetutil.Adder fun(selector: string, styleSheet: game.gui.main.stylesheetutil.Style)

---@class game.gui.main.stylesheetutil
local M = {}

---@param result table[] the stylesheet list a .css.lua's data() returns
---@return game.gui.main.stylesheetutil.Adder
function M.makeAdder(result) end

return M
