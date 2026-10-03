--- Network health from a plain snapshot of the game (see engine/snapshot.lua): counters and a
-- ranked problem list (written for the status strip and the Control Center, both since removed).
-- Pure Lua, no engine access.
--
-- Snapshot shape:
--   finance  = { cash, loan, cashflow_month, cashflow_last_month }        money in game units
--   lines    = { { id, name, carrier, vehicle_count, balance, utilization, issues = { {severity, text} } } }
--   vehicles = { { id, name, line, age_years, lifespan_years, no_path, stopped } }
-- balance: last 12 months; utilization: 0..1 or nil when unknown; severity: "problem" | "caution".
-- @module ui_overhaul.core.health
local health = {}

health.DEFAULTS = {
	old_vehicle_ratio = 1.0, -- a vehicle counts as old from this share of its lifespan
	low_utilization = 0.3, -- lines below this load are under-used
	low_cash = 0, -- cash below this is a problem
}

-- Lower rank = more urgent.
health.SEVERITY_RANK = { problem = 1, caution = 2, info = 3 }

local function settings(thresholds)
	local result = {}
	for key, value in pairs(health.DEFAULTS) do result[key] = value end
	for key, value in pairs(thresholds or {}) do result[key] = value end
	return result
end

--- True if the vehicle has reached `ratio` of its lifespan.
function health.is_old(vehicle, ratio)
	local lifespan = vehicle.lifespan_years
	if not lifespan or lifespan <= 0 or not vehicle.age_years then return false end
	return vehicle.age_years >= lifespan * (ratio or health.DEFAULTS.old_vehicle_ratio)
end

function health.is_losing(line)
	return (line.balance or 0) < 0
end

function health.has_issue(line)
	return line.issues ~= nil and #line.issues > 0
end

--- Counters: money, lines, vehicles and the number of problems and cautions.
function health.summarize(snapshot, thresholds)
	local t = settings(thresholds)
	local finance = snapshot.finance or {}
	local summary = {
		cash = finance.cash or 0,
		loan = finance.loan or 0,
		cashflow_month = finance.cashflow_month,
		cashflow_last_month = finance.cashflow_last_month,
		lines = #(snapshot.lines or {}),
		losing_lines = 0,
		issue_lines = 0,
		empty_lines = 0,
		lines_balance = 0,
		vehicles = #(snapshot.vehicles or {}),
		old_vehicles = 0,
		no_path_vehicles = 0,
	}
	for _i, line in ipairs(snapshot.lines or {}) do
		summary.lines_balance = summary.lines_balance + (line.balance or 0)
		if health.is_losing(line) then summary.losing_lines = summary.losing_lines + 1 end
		if health.has_issue(line) then summary.issue_lines = summary.issue_lines + 1 end
		if (line.vehicle_count or 0) == 0 then summary.empty_lines = summary.empty_lines + 1 end
	end
	for _i, vehicle in ipairs(snapshot.vehicles or {}) do
		if health.is_old(vehicle, t.old_vehicle_ratio) then summary.old_vehicles = summary.old_vehicles + 1 end
		if vehicle.no_path then summary.no_path_vehicles = summary.no_path_vehicles + 1 end
	end
	summary.problems, summary.cautions = 0, 0
	for _i, item in ipairs(health.problems(snapshot, thresholds)) do
		if item.severity == "problem" then summary.problems = summary.problems + 1 end
		if item.severity == "caution" then summary.cautions = summary.cautions + 1 end
	end
	return summary
end

local function add(list, item)
	item.rank = health.SEVERITY_RANK[item.severity]
	list[#list + 1] = item
end

--- Ranked problem list: most severe first, then by `weight` (bigger = worse), then by title.
-- Each item: { kind, severity, entity, title, detail, weight, actions = { ... } }.
-- `detail` values are plain data; the GUI formats and translates them.
function health.problems(snapshot, thresholds)
	local t = settings(thresholds)
	local list = {}
	local finance = snapshot.finance or {}
	if (finance.cash or 0) < t.low_cash then
		add(list, { kind = "low_cash", severity = "problem", title = "Cash", detail = { cash = finance.cash },
			weight = -(finance.cash or 0), actions = { "open_finances" } })
	end
	for _i, line in ipairs(snapshot.lines or {}) do
		if (line.vehicle_count or 0) == 0 then
			add(list, { kind = "line_empty", severity = "problem", entity = line.id, title = line.name, detail = {},
				weight = 0, actions = { "open_line_manager" } })
		end
		if health.is_losing(line) then
			add(list, { kind = "line_losing", severity = "problem", entity = line.id, title = line.name,
				detail = { balance = line.balance, utilization = line.utilization }, weight = -line.balance,
				actions = { "remove_vehicle", "open_line" } })
		end
		for _j, issue in ipairs(line.issues or {}) do
			add(list, { kind = "line_issue", severity = issue.severity or "caution", entity = line.id, title = line.name,
				detail = { text = issue.text }, weight = 0, actions = { "open_line" } })
		end
		if line.utilization and line.utilization < t.low_utilization and (line.vehicle_count or 0) > 1 then
			add(list, { kind = "line_underused", severity = "info", entity = line.id, title = line.name,
				detail = { utilization = line.utilization }, weight = t.low_utilization - line.utilization,
				actions = { "remove_vehicle", "open_line" } })
		end
	end
	for _i, vehicle in ipairs(snapshot.vehicles or {}) do
		if vehicle.no_path then
			add(list, { kind = "vehicle_no_path", severity = "problem", entity = vehicle.id, title = vehicle.name,
				detail = { line = vehicle.line }, weight = 0, actions = { "open_vehicle" } })
		end
		if health.is_old(vehicle, t.old_vehicle_ratio) then
			add(list, { kind = "vehicle_old", severity = "caution", entity = vehicle.id, title = vehicle.name,
				detail = { age_years = vehicle.age_years, lifespan_years = vehicle.lifespan_years },
				weight = vehicle.age_years / vehicle.lifespan_years, actions = { "replace_vehicle", "open_vehicle" } })
		end
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.weight ~= b.weight then return a.weight > b.weight end
		if a.title ~= b.title then return tostring(a.title) < tostring(b.title) end
		return (a.entity or 0) < (b.entity or 0)
	end)
	return list
end

--- Number of problems per kind, e.g. { line_losing = 3, vehicle_old = 7 }.
function health.count_by_kind(problems)
	local counts = {}
	for _i, item in ipairs(problems) do counts[item.kind] = (counts[item.kind] or 0) + 1 end
	return counts
end

return health
