---@meta
-- Types of gui/entity_window/eow_extension_util.d.tl (no module of its own here).

---@alias game.gui.entity_window.eow_extension_util.OwnershipState "None"|"Player"|"Foreign"

---Params of the widget plugins of an entity window (EowExtensionUtil.IEowWidgetsExtensionParams).
---@class game.gui.entity_window.eow_extension_util.IEowWidgetsExtensionParams: react.Param
---@field entityId Engine.Entity
---@field ownershipState game.gui.entity_window.eow_extension_util.OwnershipState
---@field gameCtx game.gui.main.game_context.GameContext
---@field showCalloutOnRightSide boolean
---@field setCollapsibleExpanded fun(key: string, expanded: boolean)
---@field getCollapsibleExpanded fun(key: string): boolean
---@field firstWidgetRef react.RefWrap
---@field lastWidgetRef react.RefWrap
