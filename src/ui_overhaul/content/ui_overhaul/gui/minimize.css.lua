-- Minimize button (minimize.lua): in the title bar, right-aligned before the title bar's own buttons,
-- with the close button's design (the game's fake-builtin-window-close-button style); a folded
-- window's content is not drawn and takes no space.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UioMinimizeButton BoxLayout!uio-minimize-header", { gravity = { -1, 0.5 } })
	add("R::UioMinimizeButton Button!uio-minimize", { margin = { 0, 4, 0, 4 } })
	add("R::UioMinimizeButton Button!uio-minimize ImageView", { size = { 12, 12 } })
	add("R::UioMinimizable BoxLayout!uio-folded", { visibility = "none" })
	return result
end
