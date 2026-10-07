-- Line Manager model row (lvm_models.lua): one line above the vehicle list; the model buttons scroll
-- sideways when they do not fit, "In all lines" stays at the right end. The model buttons use the
-- base "vehicle-button" style, "In all lines" the "primary" style of buttons like "Assign Line".
-- The scrolling part has a fixed width: as wide as its buttons, it ran under "In all lines" (observed
-- in game; layouts here make nothing smaller than its content). The width leaves room for the button's
-- longest text ("Dans toutes les lignes") at each text size, in the vehicle card's 500.
local ssu = require("::/gui/main/stylesheetutil.lua")

---@return table[]
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UioLvmModels !uio-lvm-models", { margin = { 0, 0, 2, 0 } })
	add("R::UioLvmModels ScrollArea!uio-lvm-models-scroll", { gravity = { -1, 0.5 }, size = { 290, -1 } })
	for font, width in pairs({ medium = 270, large = 240 }) do
		add("!font-" .. font .. " R::UioLvmModels ScrollArea!uio-lvm-models-scroll", { size = { width, -1 } })
	end
	add("R::UioLvmModels Button!uio-lvm-models-pull", { gravity = { 1, 0.5 } })
	return result
end
