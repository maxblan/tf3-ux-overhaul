--- Guarded react-replacement-config hook; the implementation is tool_stack.lua. If loading or
-- installing fails, the vanilla window behaviour stays and one line is logged.
local guard = require("/ui_overhaul/gui/guard.lua")

local stub = {}

---@param replacement_api react.ReplacementApi
function stub.doReplaceFn(replacement_api)
	local module = guard.module("ui_overhaul_1::/ui_overhaul/gui/tool_stack.lua")
	if not module then return end
	local ok, err = pcall(module.install, replacement_api)
	if not ok then debugPrint("[ui_overhaul] window behaviour not installed: ", tostring(err)) end
end

-- The engine loads *.script.lua resources by calling data().
---@return table
function data()
	return stub
end

return stub
