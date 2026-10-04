---@meta
-- Types of game_mechanics/towns/town_util_parallel.d.tl and towns.d.tl (no module of their own here):
-- what the parallel functions return.

---A town rating's level (towns.d.tl, global enum RatingLevel).
---@alias RatingLevel "VeryPoor"|"Poor"|"Mediocre"|"Good"|"VeryGood"|"Excellent"

---Result of town_util_parallel.getTownLevelWidgetState.
---@class game.game_mechanics.towns.town_util_parallel.TownLevelWidgetState
---@field experience integer
---@field growthFactor number
---@field growthLevel RatingLevel

---Param of the town_util_parallel.getRating* functions.
---@class game.game_mechanics.towns.town_util_parallel.GetRatingParam
---@field townEntity Engine.Entity
---@field extraParam any the rating's getRatingFnExtraParam, whatever that rating needs
