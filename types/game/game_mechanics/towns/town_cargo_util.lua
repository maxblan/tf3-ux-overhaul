---@meta

---@class game.game_mechanics.towns.town_cargo_util
local M = {}

---Current level, fraction of it reached, experience needed for the current and for the next level.
---@param exp integer
---@return integer level
---@return number fraction
---@return integer currentLevelExp
---@return integer nextLevelExp
function M.getLevelAndFraction(exp) end

return M
