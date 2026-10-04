---@meta

---@class game.game_mechanics.subventions.subvention_util
local M = {}

---Card data of the subsidy `state` (all four subsidy scripts call it through the module table).
---@param state game.game_mechanics.subventions.subvention.ISubvention
---@param icon string
---@return game.game_mechanics.subventions.subvention.SubventionCardData
function M.makeDefaultCardData(state, icon) end

return M
