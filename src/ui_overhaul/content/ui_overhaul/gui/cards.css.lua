-- Column widths of the mod's line-window stops table, matching the vanilla vehicle table next to it
-- (entity_window.css.lua: vehicle cell 300, age cell 98).
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local add = ssu.makeAdder(result)
	add("R::UioStopsTable R::UioStopCell", { size = { 300, -1 } })
	add("R::UioStopsTable R::UioStopWaitingCell", { size = { 98, -1 } })
	-- fixed widths like the vanilla vehicle cell (NameTextView 180 there), so the pins line up
	add("R::UioStopCell TextView!uio-stop-index", { size = { 34, -1 }, maxSize = { 34, -1 } })
	-- 34 + 220 + the terminal button (22, margin 10) fit the 300 wide cell
	add("R::UioStopsTable R::UioStopCell R::NameTextView", { size = { 220, -1 }, maxSize = { 220, -1 } })
	-- a stop the line cannot reach: greyed, as the game greys what is unavailable; the alert icon
	-- (statistics problem icon) carries the reason, so colour is not the only signal
	add("R::UioStopCell R::Component!uio-stop-unreachable TextView", { color = colorDefault.NeutralMedium })
	-- the name gives up the icon's room, so the terminal pin stays in the 300 wide cell
	add("R::UioStopsTable R::UioStopCell R::Component!uio-stop-unreachable R::NameTextView",
		{ size = { 200, -1 }, maxSize = { 200, -1 } })
	add("R::UioStopCell ImageView!uio-stop-alert", { size = { 16, 16 }, margin = { 0, 0, 0, 4 }, gravity = { 0, 0.5 } })
	-- line window Vehicles card (line_vehicles.lua): load and condition between the 180 wide name and
	-- the vehicle icon, inside the vanilla 300 wide cell
	add("R::LineVehiclesTable R::UioLineVehicleStatus BoxLayout!uio-line-vehicle-status",
		{ innerSpacing = { 4, 0 }, margin = { 0, 0, 0, 6 }, gravity = { 0, 0.5 } })
	add("R::LineVehiclesTable TextView!uio-line-vehicle-load", { size = { 40, -1 }, textAlignment = { 1, 0.5 } })
	add("R::LineVehiclesTable ImageView!uio-line-vehicle-condition", { size = { 16, 16 }, gravity = { 0, 0.5 } })
	-- industry window (industry_cards.lua): blockers in the game's warning colour, lines in a column
	add("R::UioIndustryDevelopment TextView!uio-industry-blocker", { color = colorDefault.Warning })
	add("R::UioIndustryDevelopment BoxLayout!uio-industry-development", { innerSpacing = { 0, 4 } })
	add("R::UioIndustryServedBy BoxLayout!uio-industry-lines", { innerSpacing = { 0, 2 } })
	return result
end
