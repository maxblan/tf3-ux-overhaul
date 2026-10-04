---@meta
-- Global types of scripts/gamescript.d.tl: the state a game script's functions receive.

---@class GameScriptState<T>
local GameScriptState = {}

---@return T? state nil until the script first sets it
function GameScriptState:get() end

---@param state T
function GameScriptState:set(state) end

---@return boolean
function GameScriptState:hasEventSubscriptions() end

---@param name string
function GameScriptState:subscribeToEvent(name) end

---The script's engine state, as guiUpdate sees it.
---@class GameScriptStateReadOnly<T>
local GameScriptStateReadOnly = {}

---@return T? state nil until the script first sets it
function GameScriptStateReadOnly:get() end
