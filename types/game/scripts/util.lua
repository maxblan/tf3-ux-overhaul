---@meta

---@alias game.scripts.util.DurationRounding "OnlyMonth"|"Month"|"Year"

---@class game.scripts.util
local M = {}

---The function `ref` ("file@path.to.fn") names, nil if it does not exist.
---@param ref string
---@return function?
function M.useFn(ref) end

---@param durationInDefaultSpeedMs integer
---@param currentMillisPerDay integer
---@param rounding? game.scripts.util.DurationRounding
---@return string
function M.formatDurationWithCurrentCalenderSpeed(durationInDefaultSpeedMs, currentMillisPerDay, rounding) end

return M
