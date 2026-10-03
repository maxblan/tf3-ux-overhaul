-- Line Manager row info: fixed widths so the figures form columns across rows.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UxoLvmRowInfo BoxLayout!uxo-lvm-info", { innerSpacing = { 10, 0 }, margin = { 0, 8, 0, 0 } })
	add("R::UxoLvmRowInfo TextView!uxo-lvm-count", { size = { 28, -1 }, textAlignment = { 1, 0.5 } })
	add("R::UxoLvmRowInfo TextView!uxo-lvm-money", { size = { 64, -1 }, textAlignment = { 1, 0.5 } })
	return result
end
