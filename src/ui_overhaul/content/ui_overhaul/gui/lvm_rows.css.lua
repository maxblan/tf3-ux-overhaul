-- Line Manager row info: fixed widths so the figures form columns across rows.
local ssu = require("::/gui/main/stylesheetutil.lua")

---@return table[]
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UioLvmRowInfo BoxLayout!uio-lvm-info", { innerSpacing = { 10, 0 }, margin = { 0, 8, 0, 0 } })
	-- cargo column: as wide as its icons. (A fixed 56 here never applied, its selector lacked R::, and
	-- cut the line names shorter once it did; observed in game.)
	add("R::UioLvmRowInfo BoxLayout!uio-lvm-cargo-icons", { innerSpacing = { 2, 0 }, gravity = { 0, 0.5 } })
	add("R::UioLvmRowInfo ImageView!uio-lvm-cargo-icon", { size = { 16, 16 }, margin = { 0, 0, 0, 0 },
		padding = { 0, 0, 0, 0 }, gravity = { 0, 0.5 } })
	add("R::UioLvmRowInfo TextView!uio-lvm-cargo-more", { minSize = { 16, -1 }, textAlignment = { 0, 0.5 } })
	add("R::UioLvmRowInfo TextView!uio-lvm-count", { size = { 28, -1 }, textAlignment = { 1, 0.5 } })
	add("R::UioLvmRowInfo TextView!uio-lvm-money", { size = { 64, -1 }, textAlignment = { 1, 0.5 } })
	-- vehicle rows: load and condition before the age
	add("R::UioLvmRowInfo TextView!uio-lvm-load", { size = { 40, -1 }, textAlignment = { 1, 0.5 } })
	add("R::UioLvmRowInfo ImageView!uio-lvm-condition", { size = { 16, 16 }, gravity = { 0, 0.5 } })
	-- Room for the figures in the vehicle list's rows (the list's last cell, after the vehicle's image;
	-- the hover's locate and remove buttons keep their room after them). The list's table hands out its
	-- width to every column and lays nothing smaller than its content, so the figures ran past the edge
	-- (observed in game): the check box, line and name columns get a maximum width, and the image strip
	-- a fixed one, as the game's maintenance table has it (entity_window.css.lua, R::VehicleTable). The
	-- figures then line up as a column; a long train's image scrolls in its strip, a long name is cut short.
	local lm = "Window!uio-on-line-manager R::VehicleManager "
	add(lm .. "R::ToggleSelectVehicle", { maxSize = { 32, -1 } })
	add(lm .. "R::VehicleLineSmall", { maxSize = { 32, -1 } })
	add(lm .. "R::VehicleName", { maxSize = { 130, -1 } })
	add(lm .. "R::VehicleIcon R::VehicleWidget ScrollArea!vehicle-list", { size = { 80, -1 } })
	-- wider figures at medium and large text, where "$-199 K" lost its last letter (observed in game)
	for font, widths in pairs({ medium = { 30, 72, 44 }, large = { 34, 84, 50 } }) do
		add("!font-" .. font .. " R::UioLvmRowInfo TextView!uio-lvm-count", { size = { widths[1], -1 } })
		add("!font-" .. font .. " R::UioLvmRowInfo TextView!uio-lvm-money", { size = { widths[2], -1 } })
		add("!font-" .. font .. " R::UioLvmRowInfo TextView!uio-lvm-load", { size = { widths[3], -1 } })
	end
	return result
end
