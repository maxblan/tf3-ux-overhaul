---@meta

---@class game.scripts.util.romberg
local M = {}

---Integrates `fn` from `a` over the width `h`; returns { result, error estimate }.
---@param a number
---@param h number
---@param tolerance number
---@param maxCols integer
---@param fn fun(x: number): number
---@return [number, number]
function M.rombergIntegration(a, h, tolerance, maxCols, fn) end

return M
