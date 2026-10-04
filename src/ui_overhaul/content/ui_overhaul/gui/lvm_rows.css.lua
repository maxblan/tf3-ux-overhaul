-- Line Manager row info: fixed widths so the figures form columns across rows.
local ssu = require("::/gui/main/stylesheetutil.lua")

---@return table[]
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::UioLvmRowInfo BoxLayout!uio-lvm-info", { innerSpacing = { 10, 0 }, margin = { 0, 8, 0, 0 } })
	-- cargo: three 16px icons 2px apart, or two and a "+N" of up to 20px; vanilla's line header uses 18px
	add("R::UioLvmRowInfo Component!uio-lvm-cargo", { size = { 56, -1 }, padding = { 0, 0, 0, 0 },
		margin = { 0, 0, 0, 0 } })
	add("R::UioLvmRowInfo BoxLayout!uio-lvm-cargo-icons", { innerSpacing = { 2, 0 }, gravity = { 0, 0.5 } })
	add("R::UioLvmRowInfo ImageView!uio-lvm-cargo-icon", { size = { 16, 16 }, margin = { 0, 0, 0, 0 },
		padding = { 0, 0, 0, 0 }, gravity = { 0, 0.5 } })
	add("R::UioLvmRowInfo TextView!uio-lvm-cargo-more", { minSize = { 16, -1 }, textAlignment = { 0, 0.5 } })
	add("R::UioLvmRowInfo TextView!uio-lvm-count", { size = { 28, -1 }, textAlignment = { 1, 0.5 } })
	add("R::UioLvmRowInfo TextView!uio-lvm-money", { size = { 64, -1 }, textAlignment = { 1, 0.5 } })
	-- vehicle rows: load and condition before the age
	add("R::UioLvmRowInfo TextView!uio-lvm-load", { size = { 40, -1 }, textAlignment = { 1, 0.5 } })
	add("R::UioLvmRowInfo ImageView!uio-lvm-condition", { size = { 16, 16 }, gravity = { 0, 0.5 } })
	return result
end
