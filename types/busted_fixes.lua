---@meta
-- Fixes for LuaLS's bundled luassert stub (${3rd}/luassert). luassert passes an extra last argument
-- to every assertion as the failure message (assert.is_true(ok, "why")), and tools/lua/busted.lua
-- does the same, but the stub declares only the value. These declarations add the message to the
-- assertions the specs use; LuaLS accepts a call that fits any declaration.

---@class luassert.internal
local internal = {}

---@param value any
---@param message? string
function internal.is_true(value, message) end

---@param value any
---@param message? string
function internal.is_false(value, message) end

---@param value any
---@param message? string
function internal.is_nil(value, message) end

---@param value any
---@param message? string
function internal.truthy(value, message) end

---@param value any
---@param message? string
function internal.is_truthy(value, message) end
