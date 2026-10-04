-- Minimize (minimize.lua): the window's own title is hidden; the header row in its place holds the
-- title, the rename button (styled by the game as Window::TitleLayout Button!rename) and the minimize
-- button in the close button's design (the game's fake-builtin-window-close-button style), so the
-- buttons sit right-aligned before the title bar's own ones. A folded window's content is not drawn
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
	add("BoxLayout!uio-window-header", { gravity = { -1, 0.5 } }) -- UioWindowHeader's root: class alone
	-- as the game's Window::Title (builtin.css.lua)
	add("R::UioWindowHeader TextView!uio-window-title, R::UioWindowHeader TextInputField!uio-window-title",
		{ margin = { 4, 4, 4, 4 }, padding = { 4, 4, 4, 4 }, gravity = { -1, 0.5 } })
	add("R::UioWindowHeader Button!uio-minimize", { margin = { 0, 4, 0, 4 } })
	add("R::UioWindowHeader Button!uio-minimize ImageView", { size = { 12, 12 } })
	-- on UioMinimizable's component: a class on a layout hides nothing (observed in game)
	add("R::UioMinimizable Component!uio-folded, Component!uio-folded", { visibility = "none" })
	for _i, fixed in ipairs(FIXED) do
		add(fixed[1] .. "!uio-window-folded, " .. fixed[1] .. "!window-expanded!uio-window-folded",
			{ size = { fixed[2], -1 } })
	end
	return result
end
