--- Guarded stub for performance.lua (see guard.lua): the vehicle window's Performance card (a
-- plugin, performance_card.res.lua). The store cart's tooltip is installed by installer.lua. If either
-- fails, the vanilla screen stays and one line is logged.
local react = require("::/gui/main/react.lua")
local guard = require("/ui_overhaul/gui/guard.lua")

local PERFORMANCE = "ui_overhaul_1::/ui_overhaul/gui/performance.lua"

local stub = {}

stub.UioVehiclePerformanceCard = react.RegisterRecipe("UioVehiclePerformanceCard",
	guard.plugin(PERFORMANCE, "card", "performance"))


-- The engine loads *.script.lua resources by calling data().
---@return table
function data()
	return stub
end

return stub
