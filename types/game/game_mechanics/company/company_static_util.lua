---@meta

---@class game.game_mechanics.company.company_static_util
local M = {}

---Lowest company rank that unlocks the construction (permits included), nil if none.
---@param companyMeta game.game_mechanics.company.company_metadata.ConstructionDesc
---@return integer?
function M.getMinRankConsideringPermits(companyMeta) end

return M
