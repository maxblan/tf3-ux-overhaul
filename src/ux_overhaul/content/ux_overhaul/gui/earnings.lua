--- The game bar's "Earnings" display with a richer tooltip: besides the earnings of the current
-- year it shows the cash flow of the last 30 days and of the 30 days before, so a trend is visible
-- without opening the finance window. Nothing else changes on screen.
-- Copy of the base plugin recipe GameBarEarningsPlugin (game_bar_display_earnings.script.tl),
-- registered under the same name so the base stylesheet applies; installed through a
-- react-replacement-config (earnings.script.lua). If rendering fails, the base display is shown.
-- @module ux_overhaul.gui.earnings
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local earnings_plugin = require("::/gui/game_bar/game_bar_display_earnings_plugin/game_bar_display_earnings.script.tl")

local earnings = {}

local logged = false

--- Earnings of the year and the cash flow of the last two 30-day periods (engine reads only).
local function read()
	local player = api.engine.util.getPlayer()
	local finance = api.engine.util.finance
	local t = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
	local month = api.util.getDefaultMonthDuration()
	local result = {
		year = finance.calculateEarnings(player),
		last = finance.calculateBalance({ player }, math.max(t - month, 0), t, false),
		before = finance.calculateBalance({ player }, math.max(t - 2 * month, 0), math.max(t - month, 0), false),
	}
	if not logged then
		logged = true
		debugPrint(string.format("[ux_overhaul] earnings: year=%d last30=%d before30=%d", result.year, result.last,
			result.before))
	end
	return result
end

local function tooltip(d)
	return table.concat({
		_("Total Earnings"),
		string.format("%s: %s", _("Last 30 days"), api.util.formatMoney(d.last)),
		string.format("%s: %s", _("30 days before"), api.util.formatMoney(d.before)),
	}, "\n")
end

local function render()
	local state = engine_react_util.useStepStateTimer(read)
	local d = state:old()
	if api.gui.game.isMapEditor() then return nil end
	local class = d.year >= 0 and "positive" or "negative"
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{
				meta = { tooltip = tooltip(d) },
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						builtin.TextView{ meta = { class = "font-scale-headline" }, text = _("Earnings") },
						builtin.TextView{ meta = { class = "font-scale-headline, " .. class }, text = api.util.formatMoney(d.year) },
					},
				},
			},
		},
	}
end

local Replacement = react.RegisterRecipe("GameBarEarningsPlugin", function(...)
	local ok, node = pcall(render)
	if ok then return node end
	debugPrint("[ux_overhaul] earnings display failed, showing the base one: ", tostring(node))
	return react.CallOriginalRecipe(earnings_plugin.GameBarEarningsPlugin, ...)
end)

--- Called from the react-replacement-config before the UI starts.
function earnings.install(replacement_api)
	replacement_api.ReplaceRecipe(earnings_plugin.GameBarEarningsPlugin, Replacement)
end

return earnings
