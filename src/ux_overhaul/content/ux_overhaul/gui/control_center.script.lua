--- Guarded stub registered with the engine; the implementation is control_center.lua (see guard.lua for why).
local react = require("::/gui/main/react.lua")
local guard = require("/ux_overhaul/gui/guard.lua")

local stub = {}

-- An ordinary (non-wrapper) extension point accepts any recipe as a plugin.
stub.UxoEntry = react.RegisterRecipe(
	"UxoEntry",
	guard.plugin("ux_overhaul_1::/ux_overhaul/gui/control_center.lua", "render_entry"))

-- The engine loads *.script.lua resources by calling data().
function data()
	return stub
end

return stub
