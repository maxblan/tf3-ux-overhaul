--- Income statement, cash flow statement and balance sheet from the game's finance figures.
-- Pure Lua: the GUI hands in plain copies of FinanceData (api.engine.util.finance.computeFinanceTable,
-- one value per column, costs negative) and of the company's value, and words the row keys.
--
-- The game books every journal entry under a type (income, subsidy, maintenance of vehicles or
-- infrastructure, vehicle acquisition, construction). The statements sort them:
--   income statement: revenue, subsidies and the running costs give the operating result; with
--                     other income and loan interest, the net income
--   cash flow:        net income, then investments (vehicles bought or sold, construction) and
--                     financing (loans taken and repaid) give the change in the bank account
--   balance sheet:    cash, vehicles at their depreciated value and the other assets against the
--                     debt; the difference is the company value the game shows
-- @module ui_overhaul.core.statements
local statements = {}

--- The game's JournalEntry enum values the statements sort by (api.type.JournalEntry.Type and
--- .Maintenance); the specs stand in plain numbers. They are only compared.
---@alias uo.core.statements.EntryType JournalEntry.Type|integer
---@alias uo.core.statements.EntryMaintenance JournalEntry.Maintenance|integer

---@class uo.core.statements.Enum
---@field INCOME uo.core.statements.EntryType
---@field SUBSIDY uo.core.statements.EntryType
---@field MAINTENANCE uo.core.statements.EntryType
---@field ACQUISITION uo.core.statements.EntryType
---@field CONSTRUCTION uo.core.statements.EntryType
---@field VEHICLE uo.core.statements.EntryMaintenance
---@field VEHICLE_MAINTENANCE uo.core.statements.EntryMaintenance
---@field INFRASTRUCTURE uo.core.statements.EntryMaintenance

--- A journal entry of the finance table: { type, maintenance, values } (values: one per column).
---@class uo.core.statements.Entry
---@field [1] uo.core.statements.EntryType
---@field [2] uo.core.statements.EntryMaintenance
---@field [3] number[]?

--- Plain copy of the game's FinanceData; values one per column.
---@class uo.core.statements.Data
---@field columns integer
---@field entries uo.core.statements.Entry[]
---@field other? number[]
---@field interest? number[]
---@field loanBorrowing? number[]
---@field loanRepayment? number[]
---@field balance? number[]

---@alias uo.core.statements.Kind
---| "revenue"
---| "subsidies"
---| "running_costs"
---| "vehicle_maintenance"
---| "upkeep"
---| "other_upkeep"
---| "vehicles"
---| "construction"
---| "unknown"

---@class uo.core.statements.Row
---@field key string
---@field values? number[] one per column
---@field total? boolean

--- Today's figures for the balance sheet.
---@class uo.core.statements.Values
---@field cash? number nil: unlimited money
---@field vehicles? number depreciated value
---@field assets? number the company's total assets without cash
---@field debt? number

---@class uo.core.statements.BalanceRow
---@field key string
---@field value? number
---@field total? boolean

---@param n integer
---@return number[]
local function zeros(n)
	local t = {} ---@type number[]
	for i = 1, n do t[i] = 0 end
	return t
end

---@param into number[]
---@param values? number[]
---@return number[]
local function add(into, values)
	for i = 1, #into do into[i] = into[i] + ((values and values[i]) or 0) end
	return into
end

---@param n integer
---@param ... number[]?
---@return number[]
local function sum(n, ...)
	local result = zeros(n)
	for i = 1, select("#", ...) do add(result, select(i, ...)) end
	return result
end

---@param values? number[]
---@return boolean
local function has_value(values)
	for _i, v in ipairs(values or {}) do
		if v ~= 0 then return true end
	end
	return false
end

--- Sums the journal entries by kind. `entries` = { { type, maintenance, values } }, `enum` = the
-- game's JournalEntry enums as { INCOME, SUBSIDY, MAINTENANCE, ACQUISITION, CONSTRUCTION,
-- VEHICLE, VEHICLE_MAINTENANCE, INFRASTRUCTURE }. Returns kind -> values.
---@param entries uo.core.statements.Entry[]
---@param enum uo.core.statements.Enum
---@param columns integer
---@return table<uo.core.statements.Kind, number[]>
function statements.by_kind(entries, enum, columns)
	---@type table<uo.core.statements.Kind, number[]>
	local kinds = {
		revenue = zeros(columns), subsidies = zeros(columns), running_costs = zeros(columns),
		vehicle_maintenance = zeros(columns), upkeep = zeros(columns), other_upkeep = zeros(columns),
		vehicles = zeros(columns), construction = zeros(columns), unknown = zeros(columns),
	}
	for _i, entry in ipairs(entries) do
		local t, m = entry[1], entry[2]
		local kind = "unknown" ---@type uo.core.statements.Kind
		if t == enum.INCOME then kind = "revenue"
		elseif t == enum.SUBSIDY then kind = "subsidies"
		elseif t == enum.ACQUISITION then kind = "vehicles"
		elseif t == enum.CONSTRUCTION then kind = "construction"
		elseif t == enum.MAINTENANCE then
			if m == enum.VEHICLE then kind = "running_costs"
			elseif m == enum.VEHICLE_MAINTENANCE then kind = "vehicle_maintenance"
			elseif m == enum.INFRASTRUCTURE then kind = "upkeep"
			else kind = "other_upkeep" end
		end
		add(kinds[kind], entry[3])
	end
	return kinds
end

--- The income statement and the cash flow statement as lists of rows { key, values, total = bool }.
-- `data` = { columns, entries, other, interest, loanBorrowing, loanRepayment, balance }.
-- Rows without any value are left out, except totals.
---@param data uo.core.statements.Data
---@param enum uo.core.statements.Enum
---@return uo.core.statements.Row[] income
---@return uo.core.statements.Row[] cash_flow
function statements.build(data, enum)
	local n = data.columns
	local k = statements.by_kind(data.entries, enum, n)
	local operating = sum(n, k.revenue, k.subsidies, k.running_costs, k.vehicle_maintenance, k.upkeep, k.other_upkeep)
	local net = sum(n, operating, k.unknown, data.other, data.interest)
	local investing = sum(n, k.vehicles, k.construction)
	local financing = sum(n, data.loanBorrowing, data.loanRepayment)
	local change = sum(n, net, investing, financing)

	---@param list uo.core.statements.Row[]
	---@return uo.core.statements.Row[]
	local function rows(list)
		local result = {} ---@type uo.core.statements.Row[]
		for _i, row in ipairs(list) do
			if row.total or has_value(row.values) then result[#result + 1] = row end
		end
		return result
	end
	local income = rows{
		{ key = "revenue", values = k.revenue },
		{ key = "subsidies", values = k.subsidies },
		{ key = "running_costs", values = k.running_costs },
		{ key = "vehicle_maintenance", values = k.vehicle_maintenance },
		{ key = "upkeep", values = k.upkeep },
		{ key = "other_upkeep", values = k.other_upkeep },
		{ key = "operating_result", values = operating, total = true },
		{ key = "other", values = sum(n, k.unknown, data.other) },
		{ key = "interest", values = data.interest },
		{ key = "net_income", values = net, total = true },
	}
	local cash = rows{
		{ key = "net_income", values = net },
		{ key = "vehicles", values = k.vehicles },
		{ key = "construction", values = k.construction },
		{ key = "investing", values = investing, total = true },
		{ key = "loans_taken", values = data.loanBorrowing },
		{ key = "loans_repaid", values = data.loanRepayment },
		{ key = "financing", values = financing, total = true },
		{ key = "change", values = change, total = true },
		{ key = "bank_account", values = data.balance, total = true },
	}
	return income, cash
end

--- The balance sheet as rows { key, value, total = bool }. `v` = { cash (nil: unlimited money),
-- vehicles (depreciated value), assets (the company's total assets without cash), debt }.
---@param v uo.core.statements.Values
---@return uo.core.statements.BalanceRow[]
function statements.balance_sheet(v)
	local cash = v.cash or 0
	local vehicles = math.max(0, math.min(v.vehicles or 0, v.assets or 0))
	local other = math.max(0, (v.assets or 0) - vehicles)
	local total = cash + vehicles + other
	return {
		{ key = "cash", value = v.cash },
		{ key = "vehicle_assets", value = vehicles },
		{ key = "other_assets", value = other },
		{ key = "total_assets", value = total, total = true },
		{ key = "debt", value = -(v.debt or 0) },
		{ key = "equity", value = total - (v.debt or 0), total = true },
	}
end

return statements
