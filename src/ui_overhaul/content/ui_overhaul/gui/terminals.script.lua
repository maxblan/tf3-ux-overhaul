--- Guarded react-replacement-config hook; the implementation is terminals.lua. If loading or
-- installing fails, the base terminal popover stays as it is and one line is logged.
local guard = require("/ui_overhaul/gui/guard.lua")

local stub = {}

function stub.doReplaceFn(replacement_api)
	local module = guard.module("ui_overhaul_1::/ui_overhaul/gui/terminals.lua")
	if not module then return end
	local ok, err = pcall(module.install, replacement_api)
	if not ok then debugPrint("[ui_overhaul] terminal usage buttons not installed: ", tostring(err)) end
end

-- The engine loads *.script.lua resources by calling data().
---@return table
function data()
	return stub
end

return stub
