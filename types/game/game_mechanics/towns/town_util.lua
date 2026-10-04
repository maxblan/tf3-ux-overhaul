---@meta

---A town rating (TownUtil.Rating).
---@class game.game_mechanics.towns.town_util.Rating
---@field name string
---@field icon string
---@field iconLarge string
---@field range [integer, integer]
---@field added? boolean
---@field hidden? boolean
---@field getRatingFnName ResName parallel function computing the rating level
---@field getRatingFnExtraParam any extra param of that function, whatever the rating needs
---@field key string

---@class game.game_mechanics.towns.town_util
local M = {}

---@return game.game_mechanics.towns.town_util.Rating[]
function M.GetRatings() end

---@param level integer
---@return string
function M.level2name(level) end

return M
