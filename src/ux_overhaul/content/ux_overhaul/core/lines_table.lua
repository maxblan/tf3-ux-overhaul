--- Rows of the Control Center's Lines tab: quick filters, sorting and the totals row. Works on the
-- line records of a snapshot (see core/health.lua). Pure Lua, no engine access.
-- @module ux_overhaul.core.lines_table
local health = require("/ux_overhaul/core/health.lua")

local lines_table = {}

--- Quick filters, in the order the GUI shows them.
lines_table.FILTERS = { "all", "losing", "issues", "empty", "underused" }

local predicates = {
	all = function() return true end,
	losing = health.is_losing,
	issues = health.has_issue,
	empty = function(line) return (line.vehicle_count or 0) == 0 end,
	underused = function(line, t)
		return line.utilization ~= nil and line.utilization < t.low_utilization and (line.vehicle_count or 0) > 0
	end,
}

--- Sortable columns and how to read their value.
lines_table.COLUMNS = {
	name = function(line) return string.lower(line.name or "") end,
	carrier = function(line) return line.carrier or "" end,
	vehicles = function(line) return line.vehicle_count or 0 end,
	utilization = function(line) return line.utilization or -1 end,
	balance = function(line) return line.balance or 0 end,
	issues = function(line) return line.issues and #line.issues or 0 end,
}

--- Number of lines per quick filter, for the filter buttons' labels.
function lines_table.counts(lines, thresholds)
	local t = { low_utilization = (thresholds or {}).low_utilization or health.DEFAULTS.low_utilization }
	local counts = {}
	for _i, key in ipairs(lines_table.FILTERS) do
		local n = 0
		for _j, line in ipairs(lines) do
			if predicates[key](line, t) then n = n + 1 end
		end
		counts[key] = n
	end
	return counts
end

--- Filtered and sorted copy of `lines`. `query` = { filter, sort, descending, search, thresholds };
-- ties are broken by name and id, so the order is stable between refreshes.
function lines_table.rows(lines, query)
	query = query or {}
	local predicate = predicates[query.filter or "all"] or predicates.all
	local t = { low_utilization = (query.thresholds or {}).low_utilization or health.DEFAULTS.low_utilization }
	local search = query.search and query.search ~= "" and string.lower(query.search) or nil
	local rows = {}
	for _i, line in ipairs(lines) do
		if predicate(line, t) and (not search or string.find(string.lower(line.name or ""), search, 1, true)) then
			rows[#rows + 1] = line
		end
	end
	local value = lines_table.COLUMNS[query.sort or "balance"] or lines_table.COLUMNS.balance
	local descending = query.descending == true
	table.sort(rows, function(a, b)
		local va, vb = value(a), value(b)
		if va ~= vb then
			if descending then return va > vb end
			return va < vb
		end
		local na, nb = string.lower(a.name or ""), string.lower(b.name or "")
		if na ~= nb then return na < nb end
		return (a.id or 0) < (b.id or 0)
	end)
	return rows
end

--- Totals row: count, vehicles, balance sum and vehicle-weighted average utilization (nil if unknown).
function lines_table.totals(rows)
	local totals = { lines = #rows, vehicles = 0, balance = 0 }
	local weighted, weight = 0, 0
	for _i, line in ipairs(rows) do
		local vehicles = line.vehicle_count or 0
		totals.vehicles = totals.vehicles + vehicles
		totals.balance = totals.balance + (line.balance or 0)
		if line.utilization and vehicles > 0 then
			weighted, weight = weighted + line.utilization * vehicles, weight + vehicles
		end
	end
	totals.utilization = weight > 0 and weighted / weight or nil
	return totals
end

return lines_table
