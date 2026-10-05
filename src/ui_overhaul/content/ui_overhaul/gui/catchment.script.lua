--- Guarded stubs for catchment.lua (see guard.lua): the two toggle buttons (plugins,
-- catchment_buttons.res.lua and catchment_buttons_cargo.res.lua). The map overlay is installed by
-- installer.lua. If one fails, the vanilla screen stays and one line is logged.
local react = require("::/gui/main/react.lua")
local guard = require("/ui_overhaul/gui/guard.lua")

local CATCHMENT = "ui_overhaul_1::/ui_overhaul/gui/catchment.lua"

local stub = {}

stub.UioCatchmentPerson = react.RegisterRecipe("UioCatchmentPerson",
	guard.plugin(CATCHMENT, "person_button", "catchment"))
stub.UioCatchmentCargo = react.RegisterRecipe("UioCatchmentCargo",
	guard.plugin(CATCHMENT, "cargo_button", "catchment"))


-- The engine loads *.script.lua resources by calling data().
---@return table
function data()
	return stub
end

return stub
