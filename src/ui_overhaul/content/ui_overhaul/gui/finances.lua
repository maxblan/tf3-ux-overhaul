--- Finance window, "Finances" tab: the game's figures as the three statements a business reads, next
-- to the game's own table:
--   [Income statement | Cash flow | Balance sheet | Details]
--   * Income statement: revenue, subsidies and running costs, the operating result, other income and
--     loan interest, the net income, for the same years as the game's table
--   * Cash flow: net income, vehicles bought and sold, construction, loans taken and repaid, the
--     change in the bank account and the bank account at the end of each year
--   * Balance sheet: cash, vehicles at their depreciated value, other assets, debt and the company
--     value, as of today
--   * Details: the game's own table, unchanged
-- The choice is kept for the session. The statements are built from the same
-- computeFinanceTable data as the game's table (core/statements.lua) and drawn with the table's
-- own cells and classes (the recipe ViewCell is registered under the base name).
-- Replaces the exported recipe of finances_table.tl (react-replacement-config, finances.script.lua);
-- if rendering fails, the game's table is shown.
-- @module ui_overhaul.gui.finances
local builtin = require("::/gui/main/builtin.lua")
local content_card = require("::/gui/main/content_card.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local react = require("::/gui/main/react.lua")
local base_finances_table = require("::/game_mechanics/finance/finances_table.tl")
local statements = require("/ui_overhaul/core/statements.lua")

local finances = {}

local VIEWS = { "income", "cashflow", "balance", "details" }
local view = "income" -- kept for the session

local reported = {}
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] finances: ", key, ": ", tostring(err))
end

-- Data -------------------------------------------------------------------------------------------------

local function list(values)
	local result = {}
	for i, v in ipairs(values or {}) do result[i] = v end
	return result
end

local function journal_enum()
	local J = api.type.JournalEntry
	return {
		INCOME = J.Type.INCOME, SUBSIDY = J.Type.SUBSIDY, MAINTENANCE = J.Type.MAINTENANCE,
		ACQUISITION = J.Type.ACQUISITION, CONSTRUCTION = J.Type.CONSTRUCTION,
		VEHICLE = J.Maintenance.VEHICLE, INFRASTRUCTURE = J.Maintenance.INFRASTRUCTURE,
		VEHICLE_MAINTENANCE = J.Maintenance.VEHICLE_MAINTENANCE,
	}
end

--- Plain copy of the game's finance table (4 years, as the base tab). Engine reads only.
function finances.read_table()
	local config = api.type.ChartConfig.new()
	config.count = 4
	local data = api.engine.util.finance.computeFinanceTable(api.engine.util.getPlayer(), config)
	local entries = {}
	local function collect(key, values)
		local unfolded = data:unfoldKey(key)
		entries[#entries + 1] = { unfolded[1], unfolded[2], list(values) }
	end
	data:foreach_carrier(function(carrier) data:foreach_transport(collect, carrier) end)
	data:foreach_investment(collect)
	local other = {}
	data:foreach_other(function(_key, values)
		for i, v in ipairs(values) do other[i] = (other[i] or 0) + v end
	end)
	local columns = #data.total
	for i = 1, columns do other[i] = other[i] or 0 end
	return {
		header = list(data.header),
		columns = columns,
		entries = entries,
		other = other,
		interest = list(data.interest),
		loanBorrowing = list(data.loanBorrowing),
		loanRepayment = list(data.loanRepayment),
		balance = list(data.balance),
		total = list(data.total),
	}
end

--- Today's figures for the balance sheet. Engine reads only.
function finances.read_balance()
	local player = api.engine.util.getPlayer()
	local value = api.engine.util.headquarters.getCompaniesValue()
	local vehicles = 0
	for _i, vehicle in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE)) do
		local owned = api.engine.getComponent(vehicle, api.type.ComponentType.PLAYER_OWNED)
		if owned and owned.player == player then
			vehicles = vehicles + api.engine.util.vehicle.getDepreciatedValue(vehicle)
		end
	end
	return {
		cash = api.engine.util.finance.getPlayersBalance(player),
		vehicles = vehicles,
		assets = value.totalAssets,
		debt = value.debt,
	}
end

-- Texts --------------------------------------------------------------------------------------------------

local function label(key)
	if key == "revenue" then return _("Revenue") end
	if key == "subsidies" then return _("Subsidies") end
	if key == "running_costs" then return _("Running Costs Vehicles") end
	if key == "vehicle_maintenance" then return _("Maintenance Vehicles") end
	if key == "upkeep" then return _("Upkeep Infrastructure") end
	if key == "other_upkeep" then return _("Upkeep Other") end
	if key == "operating_result" then return _("Operating result") end
	if key == "other" then return _("Other") end
	if key == "interest" then return _("Loan Interest") end
	if key == "net_income" then return _("Net income") end
	if key == "vehicles" then return _("Vehicles bought and sold") end
	if key == "construction" then return _("Construction") end
	if key == "investing" then return _("Investments") end
	if key == "loans_taken" then return _("Loans taken") end
	if key == "loans_repaid" then return _("Loans repaid") end
	if key == "financing" then return _("Loan Transactions") end
	if key == "change" then return _("Change in the bank account") end
	if key == "bank_account" then return _("Bank Account") end
	if key == "cash" then return _("Bank Account") end
	if key == "vehicle_assets" then return _("Vehicles (depreciated value)") end
	if key == "other_assets" then return _("Infrastructure and other assets") end
	if key == "total_assets" then return _("Total assets") end
	if key == "debt" then return _("Debt") end
	if key == "equity" then return _("Company Value") end
	return key
end

-- Table ----------------------------------------------------------------------------------------------------

-- The base table's cell, registered under its name so the finance stylesheet applies (finances_table.tl).
local ViewCell = react.RegisterRecipe("ViewCell", function(param)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { builtin.TextView{ meta = { class = param.class }, text = param.text } },
	}
end)

-- Row classes of the base table: alternating rows, corner classes on the first and last row.
local function row_class(index, variant, first, last)
	local class = (index % 2 == 0) and "even" or "odd"
	if variant == "First" then
		class = class .. (first and ", upper-left-corner" or last and ", upper-right-corner" or ", header")
	elseif variant == "Last" then
		class = class .. (first and ", lower-left-corner" or last and ", lower-right-corner" or ", footer")
	elseif last then
		class = class .. ", right-edge"
	elseif first then
		class = class .. ", left-edge"
	end
	return class
end

local function money_class(value)
	return (value ~= nil and value < 0) and "negative" or "positive"
end

local function row(cells_text, index, variant, total, key)
	local cells = {}
	for i, cell in ipairs(cells_text) do
		local class = "font-scale-body" .. (cell.class and (", " .. cell.class) or "")
		if i == 1 then class = class .. ", category" end
		if total then class = class .. ", uio-statement-total" end
		cells[i] = ViewCell{
			meta = { class = "cell, view, " .. row_class(index, variant, i == 1, i == #cells_text) },
			class = class,
			text = cell.text,
		}
	end
	return builtin.Row{ meta = { localKey = key }, cells = cells }
end

local function money(value)
	if value == nil then return { text = "\xE2\x88\x9E" } end -- unlimited money
	return { text = api.util.formatMoney(value), class = money_class(value) }
end

local function statement_table(header, rows, columns)
	local table_rows = { row(header, 0, "First", false, "header") }
	for i, r in ipairs(rows) do
		local cells = { { text = label(r.key) } }
		if r.values then
			for c = 1, columns do cells[#cells + 1] = money(r.values[c] or 0) end
		else
			cells[#cells + 1] = money(r.value)
		end
		table_rows[#table_rows + 1] = row(cells, i, i == #rows and "Last" or nil, r.total, r.key)
	end
	local weights = { 20 }
	for _c = 1, columns do weights[#weights + 1] = 10 end
	return builtin.Component{
		meta = { class = "table" },
		layout = builtin.BoxLayout{
			meta = { class = "table-box-layout" },
			orientation = builtin.type.Orientation.Vertical,
			children = { builtin.TableLayout{ columnWeights = weights, rows = table_rows } },
		},
	}
end

-- Tab ---------------------------------------------------------------------------------------------------------

local function view_buttons(selected, on_select)
	local labels = { _("Income statement"), _("Cash flow"), _("Balance sheet"), _("Details") }
	local buttons, index = {}, 1
	for i, key in ipairs(VIEWS) do
		buttons[i] = {
			content = builtin.TextView{ meta = { class = "font-scale-body" }, text = labels[i] },
			meta = { tag = "uio.finances.view." .. key },
		}
		if key == selected then index = i end
	end
	return builtin.ToggleButtonGroup{
		meta = { class = "uio-finances-views", id = "uio.finances.views" },
		buttons = buttons,
		selected = index,
		onValueChange = function(i) on_select(VIEWS[i]) end,
	}
end

local function render(params)
	local viewState = react.useState(view)
	local function select(key)
		view = key
		viewState:set(key)
	end
	-- lets other mods and the testbench switch the view: "uio.finances.view" <key>
	react.onEvent("uio.finances.view", function(_e, key)
		for _i, v in ipairs(VIEWS) do
			if v == key then select(key) end
		end
	end)
	-- each view reads only its own figures (the module-level `view` is the one shown); the game's
	-- own table (Details) reads for itself
	local function read(kind, reader)
		local ok, data = pcall(reader)
		if ok then return data end
		report(kind, data)
		return nil
	end
	local tableState = engine_react_util.useStepStateTimer(function(old)
		if view ~= "income" and view ~= "cashflow" then return old end
		return read("table", finances.read_table) or old
	end, 1.0)
	local balanceState = engine_react_util.useStepStateTimer(function(old)
		if view ~= "balance" then return old end
		return read("balance", finances.read_balance) or old
	end, 2.0)

	local selected = viewState:old()
	-- a view opened for the first time reads at once instead of waiting for its timer
	local table_data = tableState:old()
	if not table_data and (selected == "income" or selected == "cashflow") then
		table_data = read("table", finances.read_table)
	end
	local balance_data = balanceState:old()
	if not balance_data and selected == "balance" then balance_data = read("balance", finances.read_balance) end
	local content
	if selected == "details" then
		content = react.CallOriginalRecipe(base_finances_table, params)
	elseif selected == "balance" then
		local data = balance_data
		content = data and builtin.BoxLayout{
			orientation = builtin.type.Orientation.Vertical,
			children = {
				content_card.ContentCard{ title = _("Balance sheet") },
				statement_table({ { text = "" }, { text = _("Today") } }, statements.balance_sheet(data), 1),
			},
		} or builtin.BoxLayout{}
	else
		local data = table_data
		if data then
			local income, cash = statements.build(data, journal_enum())
			local header = { { text = "" } }
			for i = 1, data.columns do header[#header + 1] = { text = data.header[i] or "" } end
			local title = selected == "income" and _("Income statement") or _("Cash flow")
			content = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = {
					content_card.ContentCard{ title = title },
					statement_table(header, selected == "income" and income or cash, data.columns),
				},
			}
		else
			content = builtin.BoxLayout{}
		end
	end
	-- the game's table stretches through its scroll area; the statements sit at the top instead
	local children = { view_buttons(selected, select), content }
	if selected ~= "details" then children[#children + 1] = gui_react_util.makeVerticalSpacer() end
	return builtin.BoxLayout{
		meta = { class = "content-layout" },
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end

local Replacement = react.RegisterRecipe("FinancesTable", function(params)
	local ok, node = pcall(render, params)
	if ok then return node end
	report("render (showing the base table)", node)
	return builtin.BoxLayout{ children = { react.CallOriginalRecipe(base_finances_table, params) } }
end)

--- Called from the react-replacement-config before the UI starts.
function finances.install(replacement_api)
	replacement_api.ReplaceRecipe(base_finances_table, Replacement)
end

return finances
