--- Tagged logging to the game log (stdout.txt).
-- @module ux_overhaul.logger
local logger = {}

local TAG = "[ux_overhaul]"

--- Set to true for verbose diagnostics.
logger.DEBUG = false

function logger.info(...)
	debugPrint(TAG, ...)
end

function logger.debug(...)
	if logger.DEBUG then debugPrint(TAG, ...) end
end

return logger
