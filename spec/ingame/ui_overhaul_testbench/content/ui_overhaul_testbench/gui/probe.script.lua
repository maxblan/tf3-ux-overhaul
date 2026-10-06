--- Dev-only crash probe: opens window variants of increasing complexity, each re-rendering every
-- 0.25 s, so a native crash can be pinned to the last variant logged.
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local game_react_globals = require("::/gui/main/game_react_globals.tl")

local probe = {}

local H = builtin.type.Orientation.Horizontal
local V = builtin.type.Orientation.Vertical
local ICON = "::/gui/statistics/icons/alert.tga"

local function row(children, meta) return builtin.BoxLayout{ meta = meta, orientation = H, children = children } end
local function col(children) return builtin.BoxLayout{ orientation = V, children = children } end
local function text(t, meta) return builtin.TextView{ meta = meta, text = t } end

local counter = 0
-- No GUI-thread-only API inside the timer callback: a plain counter.
local function ticker()
	counter = counter + 1
	return counter
end

-- Content recipe (normal recipe inside the window) that re-renders on every tick.
local TickingContent = react.RegisterRecipe("UioProbeTickingContent",
	---@param params { rich: boolean? }
	---@return react.TreeNodeId
	function(params)
	local tick = engine_react_util.useStepStateTimer(ticker, 0.25)
	local n = tick:old()
	if params.rich then
		local children = { builtin.Button{ meta = { id = "probe.btn", tooltip = "tip" },
			content = row{ builtin.ImageView{ path = ICON }, text("rich " .. n, { class = "font-scale-headline, negative" }) },
			onClick = function() end } }
		for i = 1, n % 3 do children[#children + 1] = text("extra " .. i) end
		return col(children)
	end
	return col{ text("ticking " .. n) }
end)

---@class uo.testbench.ProbeVariant
---@field wrapper? "constant_timer"|"state"|"ticking_timer" the hooks in the window wrapper
---@field content fun(n: integer): react.TreeNodeId

-- variant -> { hooks in the window wrapper, content builder }
---@type uo.testbench.ProbeVariant[]
local VARIANTS = {
	{ wrapper = "constant_timer", content = function() return col{ text("variant 1: constant timer in wrapper") } end },
	{ wrapper = "state", content = function() return col{ text("variant 2: useState in wrapper") } end },
	{ content = function() return col{ TickingContent{} } end },
	{ content = function() return col{ TickingContent{ rich = true } } end },
	{ wrapper = "ticking_timer",
		content = function(n) return col{ text("variant 5: ticking timer in wrapper " .. n) } end },
}

local ProbeWindow
ProbeWindow = react.RegisterWrapperRecipe("UioProbeWindow", builtin.Window,
	---@param params { variant: integer }
	---@return react.TreeNodeId
	function(params)
	local variant = VARIANTS[params.variant]
	local n = 0
	if variant.wrapper == "constant_timer" then
		engine_react_util.useStepStateTimer(function() return 1 end, 0.25)
	elseif variant.wrapper == "state" then
		react.useState(0)
	elseif variant.wrapper == "ticking_timer" then
		n = engine_react_util.useStepStateTimer(ticker, 0.25):old()
	end
	return builtin.Window{
		id = "probe.window",
		title = "probe " .. params.variant,
		closable = true,
		onClose = function() game_react_globals.getDefaultWindowApi().removeAllWindows(ProbeWindow) end,
		content = variant.content(n),
	}
end)

-- Sliders as the mod changes them (sliders.lua): plain ones of 0..100 and of 0..600 in steps of 10,
-- and a construction-style parameter slider with labelled values. Logs every change.
local script_param_util = require("::/gui/main/script_param_util.tl")
local styleutil = require("::/gui/main/styleutil.tl")

local SliderWindow
SliderWindow = react.RegisterWrapperRecipe("UioProbeSliderWindow", builtin.Window, function()
	local a = react.useState(37)
	local b = react.useState(120)
	local c = react.useState(0)
	local function logged(name, state)
		return function(v)
			debugPrint("[testbench] slider ", name, " -> ", tostring(v))
			state:set(v)
		end
	end
	local numbers = {} ---@type number[]
	for i = -8, 8 do numbers[#numbers + 1] = i * 1.25 end
	return builtin.Window{
		id = "probe.sliders",
		title = "sliders",
		closable = true,
		onClose = function() game_react_globals.getDefaultWindowApi().removeAllWindows(SliderWindow) end,
		content = builtin.Component{
			meta = { styleSheet = styleutil.makeStyle{ size = { 460, -1 }, padding = { 8, 8, 8, 8 } } },
			layout = col{
			row{ text("0..100"), builtin.Slider{ meta = { id = "probe.slider.percent" }, horizontal = true, min = 0,
				max = 100, step = 1, value = a:old(), onValueChange = logged("percent", a) } },
			row{ text("0..600 s"), builtin.Slider{ horizontal = true, min = 0, max = 600, step = 10, value = b:old(),
				onValueChange = logged("seconds", b) } },
			script_param_util.buildScriptParamCompSimple{
				scriptParam = {
					uiType = api.type.enum.ScriptParamType.Slider, name = "Height", numbers = numbers,
					formatValueFn = function(v) return api.util.formatLength(v) end,
				},
				currentValue = c:old(),
				onValueChange = logged("height", c),
				vertical = false,
			},
		} },
	}
end)

-- The block the map tooltip adds for a vehicle (vehicle_tooltip.lua), in a window, and its lines
-- logged: a hover cannot be automated.
local VehicleTooltipWindow
VehicleTooltipWindow = react.RegisterWrapperRecipe("UioProbeVehicleTooltipWindow", builtin.Window,
	---@param params { vehicle: Engine.Entity }
	---@return react.TreeNodeId
	function(params)
	local vehicle_tooltip = require("ui_overhaul_1::/ui_overhaul/gui/vehicle_tooltip.lua")
	return builtin.Window{
		id = "probe.vehicle_tooltip",
		title = "vehicle tooltip",
		closable = true,
		onClose = function() game_react_globals.getDefaultWindowApi().removeAllWindows(VehicleTooltipWindow) end,
		content = col{ vehicle_tooltip.VehicleBlock{ entityRef = { get = function() return params.vehicle end } } },
	}
end)

-- Opens the "Select Terminals" popover the way a stop row does (a check cannot click that button). The
-- stand-in recipe has the base recipe's name, so the mod's wrapper swaps it for the terminal usage buttons;
-- if the hook is missing, the stand-in renders and the check fails.
local popover_react_util = require("::/gui/main/popover_react_util.tl")
local line_util = require("::/gui/line_vehicle_mgmt/line_util.tl")

local FakeTerminalSelection = react.RegisterRecipe("TerminalSelection", function()
	return builtin.BoxLayout{ children = {
		builtin.TextView{ meta = { id = "probe.fake_terminals" }, text = "stand-in terminal selection" },
	} }
end)

-- The mod's terminal module (same Lua state, so the same instance the mod uses), for the events below.
local function mod_terminals()
	return require("ui_overhaul_1::/ui_overhaul/gui/terminals.lua")
end

-- A terminal of the stop's station group that is neither preferred nor alternative: station and
-- terminal (1-based), or nil.
---@param line Engine.Entity
---@param stop_index0 integer
---@return integer? station
---@return integer? terminal
local function free_terminal(line, stop_index0)
	local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
	local stop = component and component.stops[stop_index0 + 1]
	if not stop then return nil end -- not a line (any more), or no such stop
	local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
	---@cast group -nil -- a line stop's station group always has this component
	for s, station_entity in ipairs(group.stations) do
		local station = api.engine.getComponent(station_entity, api.type.ComponentType.STATION)
		---@cast station -nil -- the stations of a station group have this component
		for t = 1, #station.terminals do
			local used = stop.station == s - 1 and stop.terminal == t - 1
			for _i, alternative in ipairs(stop.alternativeTerminals) do
				if alternative.station == s - 1 and alternative.terminal == t - 1 then used = true end
			end
			if not used then return s, t end
		end
	end
end

probe.UioProbeEntry = react.RegisterRecipe("UioProbeEntry", function()
	react.onEvent("uio.probe", function(_e, variant)
		debugPrint("[testbench] probe variant ", variant)
		local windows = game_react_globals.getDefaultWindowApi()
		windows.removeAllWindows(ProbeWindow)
		if VARIANTS[variant] then
			windows.addSingletonWindow(ProbeWindow, { variant = variant })
			api.gui.byId.setVisible("probe.window", true)
		end
	end)

	react.onEvent("uio.debug.vehicle_tooltip", function(_e, vehicle)
		local windows = game_react_globals.getDefaultWindowApi()
		windows.removeAllWindows(VehicleTooltipWindow)
		if not vehicle then return end
		local vehicle_info = require("ui_overhaul_1::/ui_overhaul/gui/vehicle_info.lua")
		local ok, info = pcall(vehicle_info.read, vehicle)
		local ok2, lines = pcall(vehicle_info.tooltip, ok and info or nil, true)
		debugPrint("[testbench] vehicle lines ok=", tostring(ok), "/", tostring(ok2), " ",
			ok2 and lines:gsub("\n", " | ") or tostring(lines))
		windows.addSingletonWindow(VehicleTooltipWindow, { vehicle = vehicle })
		api.gui.byId.setVisible("probe.vehicle_tooltip", true)
	end)

	react.onEvent("uio.debug.industry", function(_e, entity)
		local cards = require("ui_overhaul_1::/ui_overhaul/gui/industry_cards.lua")
		local ok, facts = pcall(cards.read, entity)
		if not ok or not facts then -- facts: nil if the entity is not an industry
			debugPrint("[testbench] industry read failed: ", tostring(facts))
			return
		end
		debugPrint("[testbench] industry level ", facts.level, "/", facts.maxLevel, " chance ", facts.chance,
			" rating ", facts.productionRating, " shipped ", facts.shipped, "/", facts.output,
			" blockers ", table.concat(facts.blockers, ","), " recipes ", #facts.recipes)
		for i, recipe in ipairs(facts.recipes) do
			local parts = {} ---@type string[]
			for _j, input in ipairs(recipe.inputs) do parts[#parts + 1] = input[1] .. "x" .. input[2] end
			parts[#parts + 1] = "->"
			for _j, output in ipairs(recipe.outputs) do
				parts[#parts + 1] = output[1] .. "x" .. output[2] .. "/" .. tostring(output[3])
			end
			debugPrint("[testbench] industry recipe ", i, " ", table.concat(parts, " "))
		end
		local ok2, lines = pcall(cards.read_lines, entity)
		debugPrint("[testbench] industry served by ok=", tostring(ok2), " lines=", ok2 and #lines or tostring(lines))
	end)

	-- The income statement's sum against the game's own "Earnings" (total) per column: the net income
	-- plus the investments (vehicles bought and sold, construction) must equal it if every booking is
	-- sorted in.
	react.onEvent("uio.debug.finances", function()
		local finances = require("ui_overhaul_1::/ui_overhaul/gui/finances.lua")
		local statements = require("ui_overhaul_1::/ui_overhaul/core/statements.lua")
		local ok, data = pcall(finances.read_table)
		if not ok then
			debugPrint("[testbench] finances read failed: ", tostring(data))
			return
		end
		local J = api.type.JournalEntry
		---@type uo.core.statements.Enum
		local enum = {
			INCOME = J.Type.INCOME, SUBSIDY = J.Type.SUBSIDY, MAINTENANCE = J.Type.MAINTENANCE,
			ACQUISITION = J.Type.ACQUISITION, CONSTRUCTION = J.Type.CONSTRUCTION,
			VEHICLE = J.Maintenance.VEHICLE, INFRASTRUCTURE = J.Maintenance.INFRASTRUCTURE,
			VEHICLE_MAINTENANCE = J.Maintenance.VEHICLE_MAINTENANCE,
		}
		local income = statements.income(data, enum)
		local kinds = statements.by_kind(data.entries, enum, data.columns)
		---@type number[]
		local net = {}
		for _i, r in ipairs(income) do
			if r.key == "net_income" then net = r.values or {} end
		end
		for i = 1, data.columns do
			local investing = (kinds.vehicles[i] or 0) + (kinds.construction[i] or 0)
			debugPrint("[testbench] finances ", tostring(data.header[i]), " total=", tostring(data.total[i]),
				" net=", tostring(net[i]), " net+investing=", tostring((net[i] or 0) + investing),
				" entries=", #data.entries)
		end
	end)

	react.onEvent("uio.debug.sliders", function(_e, open)
		local windows = game_react_globals.getDefaultWindowApi()
		windows.removeAllWindows(SliderWindow)
		if open then
			windows.addSingletonWindow(SliderWindow, {})
			api.gui.byId.setVisible("probe.sliders", true)
		end
	end)

	-- The popover of the mod's terminal buttons (station and line window), as a click opens it.
	-- `p`: the line, or { line, x, y } to open it there (the gallery)
	---@param _e string
	---@param p Engine.Entity|{ line: Engine.Entity, x: number, y: number }|nil
	react.onEvent("uio.debug.terminal_button", function(_e, p)
		local windows = game_react_globals.getDefaultWindowApi()
		windows.removeAllWindows(popover_react_util.PopoverWindow)
		local line, position ---@type Engine.Entity?, Vec2f|{ x: number, y: number }
		if type(p) == "table" then
			line, position = p.line, { x = p.x, y = p.y }
		else
			-- parts of the screen (0..1), as a button's getPosition gives them
			line, position = p, { x = 0.5, y = 0.2 }
		end
		-- open() reads only x and y, as of the Vec2f a button's getPosition returns
		if line then mod_terminals().open(line, 0, position --[[@as Vec2f]], "Select Terminals") end
	end)

	-- A terminal change through the parameters of those buttons: { line, add } adds (add = true) or
	-- removes a free terminal of the line's first stop as an alternative. Logs the terminal.
	react.onEvent("uio.debug.terminal_change", function(_e, p)
		local params = mod_terminals().popover_params(p.line, 0)
		if not params then
			debugPrint("[testbench] terminal change: no such stop")
			return
		end
		local s, t = p.station, p.terminal ---@type integer?, integer?
		if not s then s, t = free_terminal(p.line, 0) end
		if not s or not t then -- they come as a pair
			debugPrint("[testbench] terminal change: no free terminal")
			return
		end
		params.commonParams.selectAlternativeTerminal(params.stopNumber, s, t, p.add)
		debugPrint("[testbench] terminal change: ", p.add and "added " or "removed ", s, ",", t)
	end)

	-- A popover of the base name with other parameters, as Terminal Selector opens it from the station
	-- window: the mod must leave it alone (the stand-in renders).
	react.onEvent("uio.debug.foreign_terminals", function(_e, line)
		local windows = game_react_globals.getDefaultWindowApi()
		windows.removeAllWindows(popover_react_util.PopoverWindow)
		if not line then return end
		windows.addWindow(popover_react_util.PopoverWindow, "uio-test-foreign-terminals", {
			onClose = function() windows.removeAllWindows(popover_react_util.PopoverWindow) end,
			x = 1000, y = 250,
			windowTitle = "Select Terminals",
			windowClass = "select-terminal, management",
			recipe = FakeTerminalSelection,
			params = { lineEntity = line, stopIndex0 = 0 },
		})
	end)

	-- Reads the line's problems the way the Stops card does, and runs the path search the add-stop
	-- hover uses from stop 1 to stop 2. Logs both.
	react.onEvent("uio.debug.reach", function(_e, line)
		local ok, data = pcall(mod_terminals().read_problems, line)
		debugPrint("[testbench] reach problems ok=", tostring(ok), " stops=", ok and data and #data.stops or -1,
			" segments=", ok and data and #data.segments or -1, ok and "" or (" " .. tostring(data)))
		local component = api.engine.getComponent(line, api.type.ComponentType.LINE)
		if not component or #component.stops < 2 then return end
		---@param stop Engine.Component.Line.Stop
		---@return NodeId[]
		local function nodes(stop)
			local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
			---@cast group -nil -- a line stop's station group always has this component
			local station = api.engine.getComponent(group.stations[stop.station + 1], api.type.ComponentType.STATION)
			---@cast station -nil -- the stop's station is one of its group's stations
			return { station.terminals[stop.terminal + 1].vehicleNodeId }
		end
		local modes = {} ---@type TransportMode[]
		for mode, on in pairs(api.engine.util.line.getLineTransportModesUnion(line) or {}) do
			if on then modes[#modes + 1] = mode end
		end
		local found, result = pcall(api.engine.util.pathfinding.findPathNodeToNode,
			nodes(component.stops[1]), nodes(component.stops[2]), modes)
		debugPrint("[testbench] reach path ok=", tostring(found), " modes=", #modes, " edges=",
			found and #result or -1, found and "" or (" " .. tostring(result)))
	end)

	react.onEvent("uio.debug.terminals", function(_e, line)
		local windows = game_react_globals.getDefaultWindowApi()
		windows.removeAllWindows(popover_react_util.PopoverWindow)
		if not line then return end
		local path = line_util.getReactLineFromGameState(line).path
		local function logged(name)
			return function(...) debugPrint("[testbench] terminals ", name, " ", table.concat({ ... }, ",")) end
		end
		windows.addWindow(popover_react_util.PopoverWindow, "uio-test-terminals", {
			onClose = function() windows.removeAllWindows(popover_react_util.PopoverWindow) end,
			x = 1000, y = 250,
			windowTitle = "Select Terminals",
			windowClass = "select-terminal, management",
			recipe = FakeTerminalSelection,
			params = {
				commonParams = {
					iconPaths = {
						problemAlert = "::/gui/statistics/icons/alert.tga",
						problemArrow = "::/gui/line_vehicle_mgmt/icons/special_arrow_down.tga",
					},
					changeMainTerminal = logged("main"),
					selectAlternativeTerminal = logged("alternative"),
				},
				viaState = { old = function() return path end },
				lineEntity = line,
				stopNumber = 1, -- path index of the first stop
				stopIndex = 0,  -- API stop index (0-based)
				stopCount = #path,
				index2problems = {},
			},
		})
	end)
	return builtin.BoxLayout{}
end)

probe.COUNT = #VARIANTS

--- react-replacement-config hook: loading this module already registered its recipes.
function probe.preload()
	debugPrint("[testbench] probe recipes registered before UI start")
end

---@return table
function data()
	return probe
end

return probe
