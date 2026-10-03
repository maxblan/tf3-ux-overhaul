--- Control Center (backlog C1, C2): one window with every problem of the network, ranked, and a
-- sortable, filterable line overview, each row with its fix buttons. It is a plain window, not a
-- tool, so it stays open next to the Line Manager, Statistics and entity windows.
-- The entry point is rendered by the guarded stub control_center.script.lua.
-- @module ux_overhaul.gui.control_center
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local game_react_globals = require("::/gui/main/game_react_globals.tl")
local store = require("/ux_overhaul/engine/store.lua")
local lines_table = require("/ux_overhaul/core/lines_table.lua")
local format = require("/ux_overhaul/core/format.lua")
local actions = require("/ux_overhaul/gui/actions.lua")
local ui = require("/ux_overhaul/gui/ui.lua")

local control_center = {}

local WINDOW_ID = "uxo.cc.window"
local MAX_PROBLEM_ROWS = 150

-- What the window shows; kept for the whole session, so reopening shows the same view.
local view = { tab = "problems", filter = "all", sort = "balance", descending = false }

local function money(value)
	return api.util.formatMoney(value)
end

local function line_buttons(line)
	return {
		ui.button({ ui.icon(ui.ICONS.remove) }, function() actions.remove_vehicle(line) end,
			{ tooltip = _("Send the oldest vehicle to a depot and sell it there") }),
		ui.button({ ui.icon(ui.ICONS.add) }, function() actions.add_vehicle(line) end,
			{ tooltip = _("Buy one more vehicle like the newest one of this line") }),
		ui.button({ ui.icon(ui.ICONS.manage) }, function() actions.open_line_manager(line) end,
			{ tooltip = _("Open in the Line Manager") }),
	}
end

-- Problem rows ---------------------------------------------------------------------------------

local function problem_detail(item)
	local d = item.detail or {}
	if item.kind == "line_losing" then
		return string.format(_("Lost %s in the last 12 months"), money(-d.balance)), "negative"
	elseif item.kind == "line_empty" then
		return _("Line has no vehicles"), "negative"
	elseif item.kind == "line_issue" then
		return _(d.text or ""), item.severity == "problem" and "negative" or nil
	elseif item.kind == "line_underused" then
		return string.format(_("Only %s of the capacity is used"), format.percent(d.utilization)), nil
	elseif item.kind == "vehicle_no_path" then
		return _("Vehicle has no path"), "negative"
	elseif item.kind == "vehicle_old" then
		return string.format(_("%.0f years old, lifespan %.0f years"), d.age_years, d.lifespan_years), nil
	elseif item.kind == "low_cash" then
		return string.format(_("Cash is %s"), money(d.cash)), "negative"
	end
	return item.kind, nil
end

local SEVERITY_LABEL = { problem = "!", caution = "?", info = "i" }

local function problem_actions(item)
	if item.kind == "low_cash" then
		return { ui.button({ ui.text(_("Finances")) }, function() actions.open_finances("Finances") end) }
	elseif item.kind == "line_losing" or item.kind == "line_underused" then
		local buttons = line_buttons(item.entity)
		table.remove(buttons, 2) -- adding vehicles does not fix a losing or empty line
		return buttons
	elseif item.kind == "line_empty" or item.kind == "line_issue" then
		return { line_buttons(item.entity)[3] }
	end
	return {}
end

local function problem_row(item, index)
	local detail, class = problem_detail(item)
	local severity_class = item.severity == "problem" and "negative" or nil
	local children = {
		ui.text(SEVERITY_LABEL[item.severity] or "", ui.classes("uxo-col-severity", severity_class)),
	}
	if item.entity then
		children[#children + 1] = ui.button({ ui.text(item.title or "", "uxo-col-name") },
			function() actions.open_entity(item.entity) end, { tooltip = _("Show on the map and open its window") })
	else
		children[#children + 1] = ui.text(item.title or "", "uxo-col-name")
	end
	children[#children + 1] = ui.text(detail, ui.classes("uxo-col-detail", class))
	for _i, button in ipairs(problem_actions(item)) do children[#children + 1] = button end
	return ui.row(children, { localKey = item.kind .. ":" .. tostring(item.entity or index) })
end

local function problems_page(current)
	local problems = current.problems or {}
	local rows = {}
	for index, item in ipairs(problems) do
		if index > MAX_PROBLEM_ROWS then
			rows[#rows + 1] = ui.text(string.format(_("… and %d more"), #problems - MAX_PROBLEM_ROWS))
			break
		end
		rows[#rows + 1] = problem_row(item, index)
	end
	local summary = current.summary or { problems = 0, cautions = 0 }
	local header = #problems == 0 and ui.text(_("No problems. Everything runs."), "positive", nil, "uxo.cc.problems")
		or ui.text(string.format(_("%d problems, %d warnings, most urgent first"), summary.problems, summary.cautions),
			"font-scale-headline", nil, "uxo.cc.problems")
	table.insert(rows, 1, header)
	return ui.column(rows)
end

-- Lines page -----------------------------------------------------------------------------------

local FILTER_LABELS = {
	all = "All", losing = "Losing money", issues = "Problems", empty = "No vehicles", underused = "Under-used",
}

local COLUMNS = {
	{ key = "carrier", label = "", class = "uxo-col-carrier" },
	{ key = "name", label = "Line", class = "uxo-col-name" },
	{ key = "vehicles", label = "Vehicles", class = "uxo-col-number" },
	{ key = "utilization", label = "Load", class = "uxo-col-number" },
	{ key = "balance", label = "12 months", class = "uxo-col-money" },
	{ key = "issues", label = "Problems", class = "uxo-col-number" },
}

local function line_row(line)
	local issue_texts = {}
	for _i, issue in ipairs(line.issues or {}) do issue_texts[#issue_texts + 1] = _(issue.text) end
	local carrier_icon = ui.ICONS.carrier[line.carrier or ""]
	return ui.row({
		carrier_icon and ui.icon(carrier_icon, line.carrier) or ui.text("", "uxo-col-carrier"),
		ui.button({ ui.text(line.name, "uxo-col-name") }, function() actions.open_entity(line.id) end,
			{ tooltip = _("Show on the map and open the line window") }),
		ui.text(tostring(line.vehicle_count), "uxo-col-number"),
		ui.text(format.percent(line.utilization), "uxo-col-number"),
		ui.text(money(line.balance), ui.classes("uxo-col-money", ui.sign_class(line.balance))),
		ui.text(#issue_texts > 0 and tostring(#issue_texts) or "", "uxo-col-number, negative",
			#issue_texts > 0 and table.concat(issue_texts, "\n") or nil),
		ui.row(line_buttons(line.id)),
	}, { localKey = tostring(line.id) })
end

local function lines_page(current, rerender)
	local lines = current.data and current.data.lines or {}
	local counts = lines_table.counts(lines)
	local filter_buttons = {}
	for _i, key in ipairs(lines_table.FILTERS) do
		local label = string.format("%s (%d)", _(FILTER_LABELS[key]), counts[key])
		filter_buttons[#filter_buttons + 1] = ui.button({ ui.text(label, ui.selected(view.filter == key)) },
			function() view.filter = key; rerender() end, { id = "uxo.cc.filter." .. key })
	end
	local header = {}
	for _i, column in ipairs(COLUMNS) do
		local arrow = view.sort == column.key and (view.descending and " \xE2\x96\xBC" or " \xE2\x96\xB2") or ""
		header[#header + 1] = ui.button({ ui.text(_(column.label) .. arrow, column.class) }, function()
			if view.sort == column.key then view.descending = not view.descending
			else view.sort, view.descending = column.key, false end
			rerender()
		end, { tooltip = _("Sort") })
	end
	local rows = lines_table.rows(lines, view)
	local body = {}
	for _i, line in ipairs(rows) do body[#body + 1] = line_row(line) end
	local totals = lines_table.totals(rows)
	local footer = ui.row({
		ui.text("", "uxo-col-carrier"),
		ui.text(string.format(_("%d lines"), totals.lines), "uxo-col-name, font-scale-headline", nil, "uxo.cc.lines"),
		ui.text(tostring(totals.vehicles), "uxo-col-number, font-scale-headline"),
		ui.text(format.percent(totals.utilization), "uxo-col-number, font-scale-headline"),
		ui.text(money(totals.balance), ui.classes("uxo-col-money", "font-scale-headline", ui.sign_class(totals.balance))),
	})
	return ui.column({
		ui.row(filter_buttons),
		ui.row(header),
		ui.column(body),
		footer,
	})
end

-- Window -----------------------------------------------------------------------------------------

local ControlCenterWindow
local function render_window(params)
	local tick = react.useState(0)
	local function rerender() tick:set(tick:old() + 1) end
	local revision = engine_react_util.useStepStateTimer(function() return store.get().revision end, 1.0)
	revision:old() -- subscribes to new snapshots, so the window re-renders when one arrives
	local applied = react.useRef(nil)
	if params.request and applied:get() ~= params.request.n then
		applied:set(params.request.n)
		if params.request.tab then view.tab = params.request.tab end
		if params.request.filter then view.filter = params.request.filter end
	end

	local current = store.get()
	local summary = current.summary or { problems = 0, cautions = 0, lines = 0 }
	local tabs = {
		ui.button({ ui.text(string.format(_("Problems (%d)"), summary.problems + summary.cautions),
			ui.selected(view.tab == "problems")) },
			function() view.tab = "problems"; rerender() end, { id = "uxo.cc.tab.problems" }),
		ui.button({ ui.text(string.format(_("Lines (%d)"), summary.lines), ui.selected(view.tab == "lines")) },
			function() view.tab = "lines"; rerender() end, { id = "uxo.cc.tab.lines" }),
	}
	local page = view.tab == "lines" and lines_page(current, rerender) or problems_page(current)
	return builtin.Window{
		id = WINDOW_ID,
		meta = { class = "uxo-control-center" },
		title = _("Control Center"),
		closable = true,
		pinnable = false,
		onClose = function() game_react_globals.getDefaultWindowApi().removeAllWindows(ControlCenterWindow) end,
		content = ui.column({
			ui.row(tabs),
			builtin.ScrollArea{
				meta = { class = "uxo-cc-scroll" },
				horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
				verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
				content = builtin.Component{ layout = page },
			},
		}),
	}
end

-- A wrapper recipe may return no node, which is the safe result when rendering fails.
ControlCenterWindow = react.RegisterWrapperRecipe("UxoControlCenterWindow", builtin.Window, function(params)
	local ok, result = pcall(render_window, params)
	if ok then return result end
	debugPrint("[ux_overhaul] Control Center failed: ", tostring(result))
	return nil
end)

local requests = 0

local function open(param)
	requests = requests + 1
	param = param or {}
	local windows = game_react_globals.getDefaultWindowApi()
	windows.addSingletonWindow(ControlCenterWindow, { request = { n = requests, tab = param.tab, filter = param.filter } })
	windows.moveSingletonWindowToFront(ControlCenterWindow)
	api.gui.byId.setVisible(WINDOW_ID, true)
end

--- Plugin body for ::ModEntryPointExtension, a headless root that owns the mod's events.
-- "uxo.open" { tab, filter } opens the Control Center; "uxo.action" { name, entity } runs an action by
-- name (add_vehicle, remove_vehicle, open_entity, open_line_manager), for other mods and the testbench.
function control_center.render_entry()
	react.onEvent(actions.OPEN_EVENT, function(_e, param) open(param) end)
	react.onEvent(actions.ACTION_EVENT, function(_e, param) actions.run(param) end)
	react.onStepTimer(store.refresh, store.REFRESH_SECONDS)
	return ui.row({})
end

return control_center
