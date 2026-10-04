---@meta
-- Types of gui/entity_window/industry/industry_eow.d.tl (no module of its own here).

---The part of IndustryEow.IndustryEowState the mod reads.
---@class game.gui.entity_window.industry.industry_eow.IndustryEowState
---@field failedExpansion boolean the window's own expansion check still finds something in the way

---Params of the industry window's widget plugins (IndustryEow.IndustryWidgetPluginParams).
---@class game.gui.entity_window.industry.industry_eow.IndustryWidgetPluginParams: game.gui.entity_window.eow_extension_util.IEowWidgetsExtensionParams
---@field state game.gui.entity_window.industry.industry_eow.IndustryEowState
