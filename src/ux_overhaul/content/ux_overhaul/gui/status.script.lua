--- Guarded stub registered with the engine; the implementation is status.lua (see guard.lua for why).
local react = require("::/gui/main/react.lua")
local guard = require("/ux_overhaul/gui/guard.lua")

local stub = {}

-- An ordinary (non-wrapper) extension point accepts any recipe as a plugin.
stub.UxoStatusStrip = react.RegisterRecipe(
	"UxoStatusStrip",
	guard.plugin("ux_overhaul_1::/ux_overhaul/gui/status.lua", "render"))

-- The engine loads *.script.lua resources by calling data().
function data()
	return stub
end

return stub
