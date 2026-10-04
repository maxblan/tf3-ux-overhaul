---@meta

---A company's progression (CompaniesGrowthState.CompanyData).
---@class game.game_mechanics.company.company_progression_util.CompanyData
---@field experience integer
---@field level integer
---@field potentialLevel integer
---@field ticketPriceMultiplier number

---@class game.game_mechanics.company.company_progression_util
local M = {}

---nil before the progression game script has state for the company.
---@param entity Engine.Entity
---@return game.game_mechanics.company.company_progression_util.CompanyData?
function M.getCompanyProgressionState(entity) end

return M
