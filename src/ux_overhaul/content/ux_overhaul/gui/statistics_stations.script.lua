--- Guarded react-replacement-config hook; the implementation is statistics_stations.lua. If loading or
-- installing fails, the base tab stays and one line is logged.
local guard = require("/ux_overhaul/gui/guard.lua")

local stub = {}

function stub.doReplaceFn(replacement_api)
	local module = guard.module("ux_overhaul_1::/ux_overhaul/gui/statistics_stations.lua")
	if not module then return end
	local ok, err = pcall(module.install, replacement_api)
	if not ok then debugPrint("[ux_overhaul] statistics stations tab not installed: ", tostring(err)) end
end

-- The engine loads *.script.lua resources by calling data().
function data()
	return stub
end

return stub
