-- Line Manager model row (lvm_models.lua): one line above the vehicle list; the model buttons scroll
-- sideways when they do not fit, "In all lines" stays at the right end. The model buttons use the
-- base "vehicle-button" style, "In all lines" the "primary" style of buttons like "Assign Line".
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UioLvmModels !uio-lvm-models", { margin = { 0, 0, 2, 0 } })
	add("R::UioLvmModels ScrollArea!uio-lvm-models-scroll", { gravity = { -1, 0.5 } })
	add("R::UioLvmModels Button!uio-lvm-models-pull", { gravity = { 1, 0.5 } })
	return result
end
