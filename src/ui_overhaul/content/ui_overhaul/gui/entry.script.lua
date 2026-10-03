--- Guarded stub registered with the engine; the implementation is entry.lua (see guard.lua for why).
local react = require("::/gui/main/react.lua")
local guard = require("/ui_overhaul/gui/guard.lua")

local stub = {}

-- An ordinary (non-wrapper) extension point accepts any recipe as a plugin.
stub.UioEntry = react.RegisterRecipe("UioEntry", guard.plugin("ui_overhaul_1::/ui_overhaul/gui/entry.lua", "render"))

-- The engine loads *.script.lua resources by calling data().
function data()
	return stub
end

return stub
