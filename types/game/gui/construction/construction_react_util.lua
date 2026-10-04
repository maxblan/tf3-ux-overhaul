---@meta

---Tabs per menu: { tab, items }[] per menu.
---@alias game.gui.construction.construction_react_util.MenuCategories table<game.gui.construction.construction_menu.ConstructionMenu, [game.gui.construction.construction_menu.ConstructionMenuCategory, game.gui.construction.construction_menu.ConstructionDefinition[]][]>

---@class game.gui.construction.construction_react_util
local M = {}

---@param repository game.gui.construction.construction_menu.ConstructionActionRepository
---@return game.gui.construction.construction_react_util.MenuCategories
function M.getMenuCategories(repository) end

---@param definition game.gui.construction.construction_menu.ConstructionDefinition
---@param params table<string, number>
---@param repository game.gui.construction.construction_menu.ConstructionActionRepository
---@param isGamepadMode boolean
---@param refParams react.RefWrapApi<game.gui.construction.construction_menu.ConstructionMenuParamsAPI>
---@param entity Engine.Entity
---@param accessNotificationCacheFn fun(entity: Engine.Entity): game.game_mechanics.notifications.notifications.Notification[]
---@param sublistParamsApi react.RefWrapApi<game.gui.construction.construction_menu.ConstructionMenuParamsAPI>
---@return game.gui.construction.construction_menu.ConstructionMenuActionParams
function M.getActionParams(definition, params, repository, isGamepadMode, refParams, entity,
	accessNotificationCacheFn, sublistParamsApi) end

return M
