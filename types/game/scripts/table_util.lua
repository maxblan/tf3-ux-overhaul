---@meta

---@class game.scripts.table_util
local M = {}

---@param arg1 any any two values
---@param arg2 any
---@param allowFunctions? boolean
---@param key? any table key the recursion starts at, any key type
---@return boolean
function M.deepEquals(arg1, arg2, allowFunctions, key) end

---Deep copy.
---@generic T
---@param obj T
---@return T
function M.copy(obj) end

---@generic T
---@param obj T a table
---@return T
function M.shallowCopy(obj) end

---@generic T
---@param arr T[]
---@param value T
---@return boolean
function M.arrayContains(arr, value) end

return M
