---@meta
-- Types of gui/main/game_context.d.tl (no module of its own here), the fields this repo uses.

---@class game.gui.main.game_context.GameContext.Filters.ProtectionConfig.Line
---@field stationGroups table<Engine.Entity, boolean>

---What a mission protects of an entity (true: all of it).
---@class game.gui.main.game_context.GameContext.Filters.ProtectionConfig
---@field line? game.gui.main.game_context.GameContext.Filters.ProtectionConfig.Line

---@class game.gui.main.game_context.GameContext.Filters
---@field protectedEntities table<Engine.Entity, game.gui.main.game_context.GameContext.Filters.ProtectionConfig|boolean>

---The game's GUI context, passed to most of the game's recipes.
---@class game.gui.main.game_context.GameContext
---@field filters react.Ref<game.gui.main.game_context.GameContext.Filters>
