-- Line Manager "Select Terminals" popover: the usage buttons take the place of the base drop-down list
-- (line_vehicle_mgmt.css.lua: R::TerminalSelection ComboBox, 100 / 110 / 120 wide, 28 high), so the
-- rows are wider than the base rows (416) by about the buttons' extra width.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	add("!font-small R::TerminalSelection R::Component!main!uio-terminal-row", { size = { 540, -1 } })
	add("!font-medium R::TerminalSelection R::Component!main!uio-terminal-row", { size = { 570, -1 } })
	add("!font-large R::TerminalSelection R::Component!main!uio-terminal-row", { size = { 600, -1 } })

	add("R::TerminalSelection ToggleButtonGroup", { margin = { 0, 0, 0, 0 }, gravity = { 1, 0.5 } })
	add("R::TerminalSelection ToggleButtonGroup ToggleButton", { size = { -1, 28 }, padding = { 2, 8, 2, 8 } })
	-- as the Line Manager's other toggle group (R::CargoFilterContent), so unchecked buttons stand out
	add("R::TerminalSelection ToggleButtonGroup!horizontal ToggleButton!unchecked", {
		backgroundColor1 = colorDefault.BaseDark,
	})
	return result
end
