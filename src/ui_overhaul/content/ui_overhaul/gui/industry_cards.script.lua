--- Guarded stub registered with the engine; the implementation is industry_cards.lua (see guard.lua).
local react = require("::/gui/main/react.lua")
local guard = require("/ui_overhaul/gui/guard.lua")

local CARDS = "ui_overhaul_1::/ui_overhaul/gui/industry_cards.lua"

local stub = {}

stub.UioIndustryCards = react.RegisterRecipe("UioIndustryCards", guard.plugin(CARDS, "industry", "industry"))


-- The engine loads *.script.lua resources by calling data().
---@return table
function data()
	return stub
end

return stub
