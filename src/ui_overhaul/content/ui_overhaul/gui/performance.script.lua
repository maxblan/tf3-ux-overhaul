--- Guarded stubs for performance.lua (see guard.lua): the vehicle window's Performance card (a
-- plugin, performance_card.res.lua) and the store cart's tooltip (a react-replacement-config,
-- performance.res.lua). If either fails, the vanilla screen stays and one line is logged.
local react = require("::/gui/main/react.lua")
local guard = require("/ui_overhaul/gui/guard.lua")

local PERFORMANCE = "ui_overhaul_1::/ui_overhaul/gui/performance.lua"

local stub = {}

stub.UioVehiclePerformanceCard = react.RegisterRecipe("UioVehiclePerformanceCard", guard.plugin(PERFORMANCE, "card"))

---@param replacement_api react.ReplacementApi
function stub.doReplaceFn(replacement_api)
	local module = guard.module(PERFORMANCE)
	if not module then return end
	local ok, err = pcall(module.install, replacement_api)
	if not ok then debugPrint("[ui_overhaul] performance tooltip not installed: ", tostring(err)) end
end

-- The engine loads *.script.lua resources by calling data().
---@return table
function data()
	return stub
end

return stub
