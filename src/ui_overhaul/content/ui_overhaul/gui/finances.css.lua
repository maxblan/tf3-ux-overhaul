-- Finance window (finances.lua): totals of the statements in the medium weight the game uses for
-- headlines, and the view buttons spaced like the window's other button rows.
-- The view buttons get the game's segmented toggle look back (builtin.css.lua): the finance stylesheet
-- makes every ToggleButton in the table transparent, for its clickable cells, which left the view
-- buttons looking like plain text.
local color_util = require("::/gui/main/color_util.tl")
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::FinancesTable TextView!uio-statement-total", { fontWeight = "Medium" })
	add("R::FinancesTable ToggleButtonGroup!uio-finances-views", { margin = { 0, 0, 8, 0 }, gravity = { 0, 0 } })

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local accent = colorDefault.AccentMedium
	local views = "R::FinancesTable ToggleButtonGroup!uio-finances-views ToggleButton"
	add(views, { padding = { 6, 12, 6, 12 } })
	add(views .. "!unchecked", { backgroundColor1 = colorDefault.BaseMedium, borderColor = colorDefault.AccentVeryDark })
	add(views .. "!checked", { backgroundColor1 = accent, borderColor = colorDefault.Invisible })
	add(views .. "!unchecked:hover", { backgroundColor1 = colorDefault.BaseMedium,
		borderColor = color_util.getHoverFromRaw(accent) })
	add(views .. "!checked:hover", { backgroundColor1 = color_util.getHoverFromRaw(accent),
		borderColor = colorDefault.Invisible })
	add(views .. "!unchecked:active", { backgroundColor1 = colorDefault.BaseDark,
		borderColor = color_util.getActiveFromRaw(accent) })
	add(views .. "!checked:active", { backgroundColor1 = color_util.getActiveFromRaw(accent) })
	add(views .. "!checked > FloatingLayout TextView", { color = colorDefault.NeutralLightest })
	return result
end
