-- Line Manager in two columns (lvm_columns.lua): two columns of the game's width side by side, the
-- window as tall as the game makes it. The game's sizes (line_vehicle_mgmt.css.lua): the content is
-- 500 wide (lvmWindowWidth) and at most 894 tall (lvmWindowHeight); lines and vehicles are 240 tall,
-- the line panel 360, lines and vehicles have a margin of 6 below (lvmSectionDistance). Stacked, the
-- parts take 240 + 6 + 240 + 6 + 360 = 852; in columns the left one is lines + 6 + line panel and the
-- right one vehicles + 6, each again 852.
local ssu = require("::/gui/main/stylesheetutil.lua")

local COLUMN = 500 -- lvmWindowWidth
local GAP = 6 -- lvmSectionDistance
local PANEL = 360 -- lvmSectionLargeMaxHeight
local HEIGHT = 240 + GAP + 240 + GAP + PANEL -- the stacked parts
local WIDTH = COLUMN + GAP + COLUMN

---@return table[]
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	-- with mouse and keyboard only: with a gamepad the parts stay stacked (lvm_columns.lua)
	local on = "!input-mouse Window!uio-on-lvm-columns "
	add(on .. "R::ManagerWindowContent", { minSize = { WIDTH, -1 }, maxSize = { WIDTH, 894 } })
	-- with the minimize button's title row (minimize.css.lua): its height less, as there
	local both = "!input-mouse Window!uio-on-lvm-columns!uio-on-minimize "
	add(both .. "R::ManagerWindowContent", { maxSize = { WIDTH, 850 } })
	add(both .. "R::Component!uio-compact-header", { minSize = { WIDTH - 52, -1 } })
	add("R::Component!uio-lvm-left", { size = { COLUMN, -1 }, margin = { 0, GAP, 0, 0 } })
	add("R::Component!uio-lvm-right", { size = { COLUMN, -1 } })
	add(on .. "R::LineManager", { size = { -1, HEIGHT - GAP - PANEL } })
	add(on .. "R::VehicleManager", { size = { -1, HEIGHT - GAP } })
	return result
end
