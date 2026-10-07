-- Line Manager vehicle search (lvm_search.lua): the field across the vehicle card above the list, as
-- the line search sits in the top bar; "No matches found" where the rows would be.
local ssu = require("::/gui/main/stylesheetutil.lua")

---@return table[]
function data()
	local result = {}
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local add = ssu.makeAdder(result)
	add("R::Component!uio-vehicle-search", { margin = { 4, 4, 2, 4 } })
	add("R::Component!uio-vehicle-search TextInputField!uio-vehicle-search-field", { gravity = { -1, 0 } })
	add("R::Component!uio-vehicle-search-none", { margin = { 8, 8, 8, 8 } })
	add("TextView!uio-vehicle-search-none-text", { gravity = { 0.5, 0 }, color = colorDefault.NeutralLight })
	return result
end
