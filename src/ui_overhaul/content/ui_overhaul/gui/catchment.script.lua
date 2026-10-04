--- Guarded stubs for catchment.lua (see guard.lua): the two toggle buttons (plugins,
-- catchment_buttons.res.lua and catchment_buttons_cargo.res.lua) and the map overlay (a
-- react-replacement-config, catchment.res.lua). If one fails, the vanilla screen stays and one line
-- is logged.
local react = require("::/gui/main/react.lua")
local guard = require("/ui_overhaul/gui/guard.lua")

local CATCHMENT = "ui_overhaul_1::/ui_overhaul/gui/catchment.lua"

local stub = {}

stub.UioCatchmentPerson = react.RegisterRecipe("UioCatchmentPerson", guard.plugin(CATCHMENT, "person_button"))
stub.UioCatchmentCargo = react.RegisterRecipe("UioCatchmentCargo", guard.plugin(CATCHMENT, "cargo_button"))

function stub.doReplaceFn(replacement_api)
	local module = guard.module(CATCHMENT)
	if not module then return end
	local ok, err = pcall(module.install, replacement_api)
	if not ok then debugPrint("[ui_overhaul] catchment overlay not installed: ", tostring(err)) end
end

-- The engine loads *.script.lua resources by calling data().
function data()
	return stub
end

return stub
