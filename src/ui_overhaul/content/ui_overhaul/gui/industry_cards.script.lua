--- Guarded stub registered with the engine; the implementation is industry_cards.lua (see guard.lua).
local react = require("::/gui/main/react.lua")
local guard = require("/ui_overhaul/gui/guard.lua")

local CARDS = "ui_overhaul_1::/ui_overhaul/gui/industry_cards.lua"

local stub = {}

stub.UioIndustryCards = react.RegisterRecipe("UioIndustryCards", guard.plugin(CARDS, "industry"))

-- The switch for the red area of a blocked expansion (industry_window.res.lua).
function stub.doReplaceFn(replacement_api)
	local module = guard.module(CARDS)
	if not module then return end
	local ok, err = pcall(module.install, replacement_api)
	if not ok then debugPrint("[ui_overhaul] industry blocked-area switch not installed: ", tostring(err)) end
end

-- The engine loads *.script.lua resources by calling data().
function data()
	return stub
end

return stub
