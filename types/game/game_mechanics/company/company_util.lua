---@meta

---Why a construction cannot be built (CompanyUtil.ItemDisableReason).
---@class game.game_mechanics.company.company_util.ItemDisableReason
---@field reason string
---@field elapsedCooldownFraction? number
---@field category? string e.g. "company-rank"
---@field numRemaining? integer

---@class game.game_mechanics.company.company_util.CooldownState
---@field remainingMs number
---@field elapsedFraction number

---Company state shared by the checks of one menu (CompanyUtil.ConstructionDisableCacheData).
---@class game.game_mechanics.company.company_util.ConstructionDisableCacheData
---@field companyRank integer
---@field extraPermits table<ResName, integer>
---@field maximumPermits table<ResName, integer> extra permits included
---@field consumedPermits table<ResName, integer>
---@field remainingPermitCooldown table<ResName, game.game_mechanics.company.company_util.CooldownState>

---@class game.game_mechanics.company.company_util
local M = {}

---nil when the construction can be built.
---@param constructionRes ResName
---@param metadata ConstructionDescMetadata
---@param cache game.game_mechanics.company.company_util.ConstructionDisableCacheData
---@return game.game_mechanics.company.company_util.ItemDisableReason?
function M.getConstructionDisableReason(constructionRes, metadata, cache) end

return M
