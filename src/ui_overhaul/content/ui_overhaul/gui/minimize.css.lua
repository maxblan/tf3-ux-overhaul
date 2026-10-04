-- Minimize button in the top right corner of entity windows (minimize.lua): the size of the title
-- bar's buttons (entity_window.css.lua: locate and close, 22 x 22), a little inside the corner.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UioMinimizable Button!uio-minimize", { size = { 22, 22 }, padding = { 2, 2, 2, 2 }, margin = { 4, 4, 0, 0 } })
	add("R::UioMinimizable BoxLayout!uio-minimized", { padding = { 2, 2, 2, 2 } })
	return result
end
