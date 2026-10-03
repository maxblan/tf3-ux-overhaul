--- Guarded stubs registered with the engine; the implementation is cards.lua (see guard.lua for why).
local react = require("::/gui/main/react.lua")
local guard = require("/ui_overhaul/gui/guard.lua")

local CARDS = "ui_overhaul_1::/ui_overhaul/gui/cards.lua"

local stub = {}

-- The line-window extension point is an ordinary (non-wrapper) one and accepts any recipe.
stub.UioLineCard = react.RegisterRecipe("UioLineCard", guard.plugin(CARDS, "line"))

-- The engine loads *.script.lua resources by calling data().
function data()
	return stub
end

return stub
