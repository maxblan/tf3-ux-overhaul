---@meta
-- api.util, typed after apidef/api/util.d.tl. Only what this repository uses.

---@class ApiUtil
---@field toStringPercent fun(percentage: number): string
---@field toStringPercentPrecision fun(percentage: number, decimals: integer): string
---@field formatSpeed fun(speed: number): string
---Money as text with the currency; nil = infinite money.
---@field formatMoney fun(money: integer?): string
---@field getDefaultMonthDuration fun(): integer
---@field getDefaultYearDuration fun(): integer
---@field formatSeconds fun(seconds: integer): string
---@field formatKMB fun(number: number): string
---Only on the GUI thread: crashes the game in a step timer callback.
---@field getApplicationTime fun(): number
---Only on the GUI thread.
---@field getInputMode fun(): InputMode
---@field getAppConfig fun(): AppConfig
local ApiUtil = {}

---@param meters number
---@param decimals? integer
---@param forceSmallUnit? boolean
---@return string
function ApiUtil.formatLength(meters, decimals, forceSmallUnit) end

---@param seconds integer
---@param hideZeroSeconds? boolean
---@return string
function ApiUtil.formatMinutesSeconds(seconds, hideZeroSeconds) end
