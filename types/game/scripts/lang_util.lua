---@meta

---@class game.scripts.lang_util
local M = {}

---Replaces each {key} in `text` by values[key] (string.interp; numbers are written as by tostring).
---@param text string
---@param values table<string, string|number>
---@return string
function M.format(text, values) end

---@param value integer
---@return string
function M.formatInt(value) end

---@param value number
---@param decimals integer
---@return string
function M.formatNumber(value, decimals) end

---@param text string
---@param part string
---@return boolean
function M.stringContains(text, part) end

return M
