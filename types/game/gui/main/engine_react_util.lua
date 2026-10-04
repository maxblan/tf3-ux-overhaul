---@meta

---Commits a new state, optionally sending `cmd`; `callback` gets the command's result.
---@alias game.gui.main.engine_react_util.CommitFn<S> fun(state: S, cmd?: Command, callback?: fun(cmdData: ICommandData, success: boolean, affectedEntities: [Engine.Entity, Engine.Revision][]))

---@class game.gui.main.engine_react_util
local M = {}

---State read from the engine every step; `getFromEngine` gets the old value (nil the first time).
---@generic S
---@param getFromEngine fun(old?: S): S
---@param makeCommand? fun(state: S): (Command, fun(cmdData: ICommandData, success: boolean, affectedEntities: [Engine.Entity, Engine.Revision][])?)
---@param stateEqualsFn? fun(a: S, b: S): boolean default table_util.deepEquals
---@param onChange? fun(now: S, old: S, commit: boolean)
---@param once? boolean
---@return react.State<S>
---@return game.gui.main.engine_react_util.CommitFn<S>
function M.useStepState(getFromEngine, makeCommand, stateEqualsFn, onChange, once) end

---As useStepState, but read every `interval` seconds (default 0.5) in a deferred step.
---@generic S
---@param getFromEngine fun(old?: S): S
---@param interval? number
---@param stateEqualsFn? fun(a: S, b: S): boolean default table_util.deepEquals
---@return react.State<S>
function M.useStepStateTimer(getFromEngine, interval, stateEqualsFn) end

---@generic S
---@param getFromEngine fun(old?: S): S
---@param interval? number
---@param makeCommand? fun(state: S): (Command, fun(cmdData: ICommandData, success: boolean, affectedEntities: [Engine.Entity, Engine.Revision][])?)
---@param stateEqualsFn? fun(a: S, b: S): boolean default table_util.deepEquals
---@param onChange? fun(now: S, old: S, commit: boolean)
---@param once? boolean
---@return react.State<S>
---@return game.gui.main.engine_react_util.CommitFn<S>
function M.useStepStateTimerWithCommit(getFromEngine, interval, makeCommand, stateEqualsFn, onChange, once) end

---State computed each step in another thread by useFn(`useFnName`)(`useFnParams`); nil until the
---first result arrives. Annotate the local as react.State<Result?> to type it.
---@param useFnName string
---@param useFnParams any the parallel function's param, any value it accepts
---@param stateEqualsFn? fun(a: any, b: any): boolean
---@return react.State<any> the parallel function's result
---@return game.gui.main.engine_react_util.CommitFn<any>
function M.useStepStateParallelSimple(useFnName, useFnParams, stateEqualsFn) end

return M
