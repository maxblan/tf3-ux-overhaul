-- Minimize (minimize.lua): the window's own title is hidden; the header row in its place holds the
-- rename button (styled by the game as Window::TitleLayout Button!rename), the title and the minimize
-- button, which sits right-aligned before the title bar's own buttons and looks like them (the game's
-- Window::TitleLayout Button: the pin and locate buttons next to it). A folded window's content is not drawn
-- and takes no space; the windows the game gives a fixed size keep their width and lose their height.
local ssu = require("::/gui/main/stylesheetutil.lua")

-- the fixed sizes, as the game sets them: selector -> width
---@type [string, number|string][]
local FIXED = {
	{ "#menu.finance.window", 1488 }, -- finances.css.lua (financesWindowWidth)
	{ "#menu.company.window", 1488 }, -- company.css.lua
	{ "!font-small #menu.statistics.window", "80vw" }, -- statistics.css.lua, also while expanded
	{ "!font-medium #menu.statistics.window", "90vw" },
	{ "!font-large #menu.statistics.window", "96vw" },
}

---@return table[]
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("Window!uio-minimizable Window::Title", { visibility = "none" })
	-- UioWindowHeader's root (class alone): at the top of the title bar, as the game's title and close
	-- button are (gravity { -1, 0 } and { 1, 0 }, builtin.css.lua), so the buttons line up
	add("BoxLayout!uio-window-header", { gravity = { -1, 0 } })
	-- as the game's Window::Title (builtin.css.lua): fills the row, so a long title is cut short
	add("R::UioWindowHeader TextView!uio-window-title, R::UioWindowHeader TextInputField!uio-window-title",
		{ margin = { 4, 4, 4, 4 }, padding = { 4, 4, 4, 4 }, gravity = { -1, 0.5 } })
	-- in a title bar the game's rule for its buttons applies (Window::TitleLayout Button, builtin.css.lua);
	-- the symbol at the size of theirs
	add("R::UioWindowHeader Button!uio-minimize ImageView", { size = { 18, 18 } })
	-- the Line Manager's own title row lies in its content, outside a title bar: the same rule here
	add("R::Component!uio-compact-header Button!uio-minimize", {
		gravity = { 1, 0 },
		padding = { 4, 4, 4, 4 },
		margin = { 4, 0, 4, 0 },
		backgroundImage1 = {
			fileName = "::/gui/builtin/window/design/header_button_surface.tga",
			horizontal = { 0, 12, 14, 26 },
			vertical = { 0, 12, 14, 26 },
		},
		borderImage = {
			fileName = "::/gui/builtin/window/design/header_button_contour.tga",
			horizontal = { 0, 12, 14, 26 },
			vertical = { 0, 12, 14, 26 },
		},
	})
	-- the Line Manager's own title row (a compact window: no title bar): as wide as its content
	-- (lvmWindowWidth 500, line_vehicle_mgmt.css.lua; minSize counts without the padding, so 500 - 8 - 44),
	-- so it keeps that width while folded, and the minimize button clear of the engine's round close
	-- button, which sits over the window's top right corner
	add("R::Component!uio-compact-header", { minSize = { 448, -1 }, padding = { 4, 44, 0, 8 } })
	-- the content gives up the title row's height (about 44: title, its margins and the row's padding),
	-- so the Line Manager stays as tall as the game made it (lvmWindowHeight 894)
	add("Window!uio-on-minimize R::ManagerWindowContent", { maxSize = { 500, 850 } })
	-- on UioMinimizable's component: a class on a layout hides nothing (observed in game)
	add("R::UioMinimizable R::Component!uio-folded, R::Component!uio-folded", { visibility = "none" })
	for _i, fixed in ipairs(FIXED) do
		add(fixed[1] .. "!uio-window-folded, " .. fixed[1] .. "!window-expanded!uio-window-folded",
			{ size = { fixed[2], -1 } })
	end
	return result
end
