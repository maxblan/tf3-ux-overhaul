---@meta

---Colours as { r, g, b, a } or Vec4f, sizes as { x, y } or Vec2f.
---@class game.gui.main.styleutil.StyleTable
---@field color? number[]|Vec4f
---@field borderColor? number[]|Vec4f
---@field backgroundColor? number[]|Vec4f
---@field backgroundColor1? number[]|Vec4f
---@field backgroundColor2? number[]|Vec4f
---@field borderWidth? number[]|Vec4f
---@field fontSize? integer
---@field size? number[]|Vec2f
---@field anchorPoint? number[]|Vec2f

---@class game.gui.main.styleutil
local M = {}

---@param styleTable game.gui.main.styleutil.StyleTable
---@return StyleSheet
function M.makeStyle(styleTable) end

return M
