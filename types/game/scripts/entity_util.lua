---@meta

---@class game.scripts.entity_util.EntityAndRevision
---@field entity Engine.Entity
---@field revision Engine.Revision

---@class game.scripts.entity_util
local M = {}

---@param entity Engine.Entity
---@return game.scripts.entity_util.EntityAndRevision
function M.makeEntityAndRevision(entity) end

---Whether the entity's revision changed (or it was deleted) since `entityAndRevision` was made.
---@param entityAndRevision game.scripts.entity_util.EntityAndRevision
---@return boolean
function M.entityChanged0(entityAndRevision) end

---@param entity Engine.Entity
---@return boolean
function M.isOwnedByPlayer(entity) end

---@param entity Engine.Entity
---@return boolean
function M.isOwnedByPlayerOrNotOwned(entity) end

return M
