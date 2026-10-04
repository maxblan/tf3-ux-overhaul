---@meta

---A colour of a .gres colour table: { r, g, b } or { r, g, b, a }.
---@alias game.gui.main.color_util.GResColor number[]

---@class game.gui.main.color_util
local M = {}

---@param enabledColor game.gui.main.color_util.GResColor
---@return game.gui.main.color_util.GResColor
function M.getHoverFromRaw(enabledColor) end

---@param enabledColor game.gui.main.color_util.GResColor
---@return game.gui.main.color_util.GResColor
function M.getActiveFromRaw(enabledColor) end

---@param gResColor game.gui.main.color_util.GResColor
---@param alpha number
---@return game.gui.main.color_util.GResColor
function M.withTransparencyRaw(gResColor, alpha) end

return M
