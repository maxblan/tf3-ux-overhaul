--- Guarded react-replacement-config hooks (installer_early.res.lua, installer_late.res.lua); the
-- implementation is installer.lua. If it fails to load, nothing is installed and the game stays vanilla.
local guard = require("/ui_overhaul/gui/guard.lua")

local INSTALLER = "ui_overhaul_1::/ui_overhaul/gui/installer.lua"

local stub = {}

---@param replacement_api react.ReplacementApi
function stub.early(replacement_api)
	guard.call(INSTALLER, "early", function() return nil end, replacement_api)
end

---@param replacement_api react.ReplacementApi
function stub.late(replacement_api)
	guard.call(INSTALLER, "late", function() return nil end, replacement_api)
end

-- The engine loads *.script.lua resources by calling data().
---@return table
function data()
	return stub
end

return stub
