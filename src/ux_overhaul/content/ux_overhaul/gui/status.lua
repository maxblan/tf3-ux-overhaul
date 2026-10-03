--- Status strip in the game bar (backlog A1): problems, losing lines, old vehicles and the cash flow
-- of the last month, always visible. Each chip opens the place where the player can act on it.
-- Rendered by the guarded stub status.script.lua.
-- @module ux_overhaul.gui.status
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local store = require("/ux_overhaul/engine/store.lua")
local format = require("/ux_overhaul/core/format.lua")
local actions = require("/ux_overhaul/gui/actions.lua")
local ui = require("/ux_overhaul/gui/ui.lua")

local status = {}

-- Only the numbers the strip shows, so the state (and the re-render) changes only when they do.
local function read()
	local current = store.get()
	local s = current.summary
	if not s then return { ready = false } end
	return {
		ready = true,
		problems = s.problems,
		cautions = s.cautions,
		losing = s.losing_lines,
		old = s.old_vehicles,
		cashflow = s.cashflow_month,
	}
end

local function chip(id, icon, text, class, tooltip, on_click)
	return ui.button({ ui.icon(icon), ui.text(text, ui.classes("font-scale-headline", class)) },
		on_click, { id = id, tooltip = tooltip, class = "uxo-chip" })
end

--- Plugin body for ::GameBarInfoDisplayExtension.
function status.render()
	local state = engine_react_util.useStepStateTimer(read, 1.0)
	local s = state:old()
	if api.gui.game.isMapEditor() or not s or not s.ready then return ui.row({}) end

	local chips = {
		chip("uxo.status.problems", ui.ICONS.alert,
			s.problems > 0 and tostring(s.problems) or _("OK"),
			s.problems > 0 and "negative" or "positive",
			string.format(_("%d problems, %d warnings. Click to see them all."), s.problems, s.cautions),
			function() actions.open_control_center("problems") end),
	}
	if s.losing > 0 then
		chips[#chips + 1] = chip("uxo.status.losing", ui.ICONS.lines, tostring(s.losing), "negative",
			string.format(_("%d lines lost money in the last 12 months. Click to see them."), s.losing),
			function() actions.open_control_center("lines", "losing") end)
	end
	if s.old > 0 then
		chips[#chips + 1] = chip("uxo.status.old", ui.ICONS.old, tostring(s.old), nil,
			string.format(_("%d vehicles have reached the end of their lifespan."), s.old),
			function() actions.open_control_center("problems") end)
	end
	if s.cashflow then
		chips[#chips + 1] = chip("uxo.status.cashflow", ui.ICONS.money, format.signed(s.cashflow),
			ui.sign_class(s.cashflow),
			_("Cash flow of the last 30 days. Click to open the finances."),
			function() actions.open_finances("Overview") end)
	end
	return ui.row(chips, { id = "uxo.status" })
end

return status
