---@meta

---@class game.game_mechanics.subventions.subvention_util
local M = {}

---Card data of the subsidy `state` (all four subsidy scripts call it through the module table).
---@param state game.game_mechanics.subventions.subvention.ISubvention
---@param icon string
---@return game.game_mechanics.subventions.subvention.SubventionCardData
function M.makeDefaultCardData(state, icon) end

---The subsidy with uid `subventionUID` in the subsidy game script's state, and its list (1 proposed,
---2 active, 3 completed, 4 failed); nil if there is none.
---@param scriptEntity Engine.Entity
---@param subventionUID number
---@return game.game_mechanics.subventions.subvention.ISubvention?
---@return integer?
function M.getSubventionAndStatusFromGameScript(scriptEntity, subventionUID) end

return M
