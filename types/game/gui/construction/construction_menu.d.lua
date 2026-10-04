---@meta
-- Types of gui/construction/construction_menu.d.tl (no module of its own here), the fields this repo uses.

---@alias game.gui.construction.construction_menu.ConstructionMenu
---| "ROAD"
---| "RAIL"
---| "WATER"
---| "AIR"
---| "ROADS"
---| "TRACKS"
---| "WAREHOUSE"
---| "PERKS"
---| "LANDSCAPING"
---| "TOWN"
---| "INDUSTRY"
---| "BULLDOZER"
---| "MODULES"
---| "MODULE_BULLDOZER"

---A tab of a construction menu.
---@class game.gui.construction.construction_menu.ConstructionMenuCategory
---@field category string
---@field menu game.gui.construction.construction_menu.ConstructionMenu
---@field name string
---@field icon ResName
---@field order? integer

---@class game.gui.construction.construction_menu.ConstructionAvailability
---@field yearFrom? integer
---@field yearTo? integer 0: no end

---An item of a construction menu.
---@class game.gui.construction.construction_menu.ConstructionDefinition
---@field resName ResName
---@field name string
---@field description? string
---@field categories? string[]
---@field availability? game.gui.construction.construction_menu.ConstructionAvailability
---@field order? integer

---What the menu's action recipe gets for the active item.
---@class game.gui.construction.construction_menu.ConstructionMenuActionParams
---@field constructionActionParams? builtin.ConstructionActionParam
---@field layerConfig? LayerConfig

---All items of the construction menus; passed on unchanged.
---@class game.gui.construction.construction_menu.ConstructionActionRepository

---Api of the construction menu's parameter panel; passed on unchanged.
---@class game.gui.construction.construction_menu.ConstructionMenuParamsAPI
