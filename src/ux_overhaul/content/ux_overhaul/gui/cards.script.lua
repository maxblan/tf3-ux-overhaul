--- Guarded stubs registered with the engine; the implementation is cards.lua (see guard.lua for why).
local react = require("::/gui/main/react.lua")
local guard = require("/ux_overhaul/gui/guard.lua")

local CARDS = "ux_overhaul_1::/ux_overhaul/gui/cards.lua"

local stub = {}

-- The line-window extension point is an ordinary (non-wrapper) ones and accept any recipe.
stub.UxoLineCard = react.RegisterRecipe("UxoLineCard", guard.plugin(CARDS, "line"))

-- The engine loads *.script.lua resources by calling data().
function data()
	return stub
end

return stub
