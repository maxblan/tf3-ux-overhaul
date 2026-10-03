-- Column widths of the Control Center rows and the size of its scroll area.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("ScrollArea!uxo-cc-scroll", { minSize = { 980, 540 } })
	add("TextView!uxo-col-severity", { minSize = { 18, -1 } })
	add("TextView!uxo-col-carrier", { minSize = { 20, -1 } })
	add("TextView!uxo-col-name", { minSize = { 240, -1 } })
	add("TextView!uxo-col-detail", { minSize = { 360, -1 } })
	add("TextView!uxo-col-number", { minSize = { 72, -1 }, textAlignment = { 1, 0.5 } })
	add("TextView!uxo-col-money", { minSize = { 120, -1 }, textAlignment = { 1, 0.5 } })
	return result
end
