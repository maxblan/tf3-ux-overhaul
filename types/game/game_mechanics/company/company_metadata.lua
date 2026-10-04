---@meta

---@alias game.game_mechanics.company.company_metadata.PerkCategory "HQ"|"LANDMARK"|"MECHANICS"|"PROSPECTION"

---Company metadata of a construction (CompanyMetadata.ConstructionDesc).
---@class game.game_mechanics.company.company_metadata.ConstructionDesc
---@field companyRank? integer
---@field headquarters? boolean
---@field maxCompanyRank? integer
---@field permitKey? ResName
---@field rankAndPermits? [integer, integer][] { rank, times }
---@field perkCategory? game.game_mechanics.company.company_metadata.PerkCategory
---@field cargoTypes? ResName[]

---@class game.game_mechanics.company.company_metadata.ConstructionDescAccessor
local ConstructionDescAccessor = {}

---The company part of a construction's metadata, nil if it has none.
---@param container ConstructionDescMetadata?
---@return game.game_mechanics.company.company_metadata.ConstructionDesc?
function ConstructionDescAccessor.get(container) end

---@class game.game_mechanics.company.company_metadata
---@field constructionDesc game.game_mechanics.company.company_metadata.ConstructionDescAccessor
local M = {}

return M
