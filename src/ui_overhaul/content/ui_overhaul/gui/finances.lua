--- Finance window, "Finances" tab: the game's own figures grouped as an income statement, next to the
-- game's own table:
--   [Income statement | Details]
--   * Income statement: revenue, subsidies and running costs, the operating result, other income and
--     loan interest, the net income, for the same years as the game's table
--   * Details: the game's own table, unchanged
-- The choice is kept for the session. The statement is built from the same computeFinanceTable data
-- as the game's table (core/statements.lua) and drawn with the table's own cells and classes (the
-- recipe ViewCell is registered under the base name).
-- Replaces the exported recipe of finances_table.tl (react-replacement-config, installer.lua);
-- if rendering fails, the game's table is shown for the rest of the session (fallback.lua).
-- @module ui_overhaul.gui.finances
local builtin = require("::/gui/main/builtin.lua")
local content_card = require("::/gui/main/content_card.tl")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local react = require("::/gui/main/react.lua")
local base_finances_table = require("::/game_mechanics/finance/finances_table.tl")
local fallback = require("/ui_overhaul/gui/fallback.lua")
local statements = require("/ui_overhaul/core/statements.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")

-- safe calls of the base recipe (guard.base)
local original_table = guard.base("FinancesTable", base_finances_table)

---@class uo.gui.finances
local finances = {}

local VIEWS = { "income", "details" }
local view = "income" -- kept for the session

local report = guard.reporter("finances: ")

-- Data -------------------------------------------------------------------------------------------------

---@param values? integer[]
---@return integer[]
---@overload fun(values: string[]): string[]
local function list(values)
	---@type integer[]
	local result = {}
	if values then
		for i, v in ipairs(values) do result[i] = v end
	end
	return result
end

---@return uo.core.statements.Enum
local function journal_enum()
	local J = api.type.JournalEntry
	return {
		INCOME = J.Type.INCOME, SUBSIDY = J.Type.SUBSIDY, MAINTENANCE = J.Type.MAINTENANCE,
		ACQUISITION = J.Type.ACQUISITION, CONSTRUCTION = J.Type.CONSTRUCTION,
		VEHICLE = J.Maintenance.VEHICLE, INFRASTRUCTURE = J.Maintenance.INFRASTRUCTURE,
		VEHICLE_MAINTENANCE = J.Maintenance.VEHICLE_MAINTENANCE,
	}
end

---@class uo.gui.finances.Table: uo.core.statements.Data
---@field header string[] the column titles (years)
---@field total integer[]

--- Plain copy of the game's finance table (4 years, as the base tab). Engine reads only.
---@return uo.gui.finances.Table
function finances.read_table()
	local config = api.type.ChartConfig.new()
	config.count = 4
	local data = api.engine.util.finance.computeFinanceTable(api.engine.util.getPlayer(), config)
	---@type uo.core.statements.Entry[]
	local entries = {}
	---@param key integer
	---@param values integer[]
	local function collect(key, values)
		local unfolded = data:unfoldKey(key)
		entries[#entries + 1] = { unfolded[1], unfolded[2], list(values) }
	end
	data:foreach_carrier(function(carrier) data:foreach_transport(collect, carrier) end)
	data:foreach_investment(collect)
	---@type integer[]
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
		total = list(data.total),
	}
end

-- Texts --------------------------------------------------------------------------------------------------

---@param key string
---@return string
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
	return key
end

-- Table ----------------------------------------------------------------------------------------------------

---@class uo.gui.finances.ViewCellParam: react.Param
---@field class string
---@field text string

-- The base table's cell, registered under its name so the finance stylesheet applies (finances_table.tl).
---@param param uo.gui.finances.ViewCellParam
---@return react.TreeNodeId
local ViewCell = react.RegisterRecipe("ViewCell", function(param)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { builtin.TextView{ meta = { class = param.class }, text = param.text } },
	}
end)

-- Row classes of the base table: alternating rows, corner classes on the first and last row.
---@param index integer
---@param variant? "First"|"Last"
---@param first boolean
---@param last boolean
---@return string
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

---@param value? number
---@return string
local function money_class(value)
	return (value ~= nil and value < 0) and "negative" or "positive"
end

---@class uo.gui.finances.Cell
---@field text string
---@field class? string

---@param cells_text uo.gui.finances.Cell[]
---@param index integer
---@param variant? "First"|"Last"
---@param total? boolean
---@param key string
---@return react.TreeNodeId
local function row(cells_text, index, variant, total, key)
	---@type react.TreeNodeId[]
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

---@param value? number nil: unlimited money
---@return uo.gui.finances.Cell
local function money(value)
	if value == nil then return { text = "\xE2\x88\x9E" } end -- unlimited money
	-- the figures are sums of the engine's integer amounts
	return { text = api.util.formatMoney(value --[[@as integer]]), class = money_class(value) }
end

---@param header uo.gui.finances.Cell[]
---@param rows uo.core.statements.Row[]
---@param columns integer
---@return react.TreeNodeId
local function statement_table(header, rows, columns)
	local table_rows = { row(header, 0, "First", false, "header") }
	for i, r in ipairs(rows) do
		---@type uo.gui.finances.Cell[]
		local cells = { { text = label(r.key) } }
		for c = 1, columns do cells[#cells + 1] = money(r.values and r.values[c] or 0) end
		table_rows[#table_rows + 1] = row(cells, i, i == #rows and "Last" or nil, r.total, r.key)
	end
	---@type number[]
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

---@param selected string
---@param on_select fun(key: string)
---@return react.TreeNodeId
local function view_buttons(selected, on_select)
	local labels = { _("Income statement"), _("Details") }
	---@type builtin.ToggleButtonGroupChildParam[], integer
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

---@param params nil the base recipe takes none; passed on unchanged
---@return react.TreeNodeId
local function render(params)
	local viewState = react.useState(view)
	---@param key string
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
	---@generic R
	---@param kind string
	---@param reader fun(): R
	---@return R?
	local function read(kind, reader)
		local ok, data = pcall(reader)
		if ok then return data end
		report(kind, data)
		return nil
	end
	---@param old? uo.gui.finances.Table
	---@return uo.gui.finances.Table?
	local tableState = engine_react_util.useStepStateTimer(function(old)
		if view ~= "income" then return old end
		return read("table", finances.read_table) or old
	end, 1.0)

	local selected = viewState:old()
	-- a view opened for the first time reads at once instead of waiting for its timer
	local table_data = tableState:old()
	if not table_data and selected == "income" then table_data = read("table", finances.read_table) end
	---@type react.TreeNodeId
	local content
	if selected == "details" then
		content = original_table.layout(params)
	else
		local data = table_data
		if data then
			---@type uo.gui.finances.Cell[]
			local header = { { text = "" } }
			for i = 1, data.columns do header[#header + 1] = { text = data.header[i] or "" } end
			content = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = {
					content_card.ContentCard{ title = _("Income statement") },
					statement_table(header, statements.income(data, journal_enum()), data.columns),
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

finances.switch = fallback.switch("finance statements")
local Replacement = fallback.replacement(finances.switch, "FinancesTable", render, base_finances_table)

--- Called by installer.lua before the UI starts.
---@param replacement_api react.ReplacementApi
function finances.install(replacement_api)
	replacement_api.ReplaceRecipe(base_finances_table, Replacement)
end

return finances
