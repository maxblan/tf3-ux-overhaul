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
local TickingContent = react.RegisterRecipe("UioProbeTickingContent", function(params)
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

-- variant -> { hooks in the window wrapper, content builder }
local VARIANTS = {
	{ wrapper = "constant_timer", content = function() return col{ text("variant 1: constant timer in wrapper") } end },
	{ wrapper = "state", content = function() return col{ text("variant 2: useState in wrapper") } end },
	{ content = function() return col{ TickingContent{} } end },
	{ content = function() return col{ TickingContent{ rich = true } } end },
	{ wrapper = "ticking_timer",
		content = function(n) return col{ text("variant 5: ticking timer in wrapper " .. n) } end },
}

local ProbeWindow
ProbeWindow = react.RegisterWrapperRecipe("UioProbeWindow", builtin.Window, function(params)
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

-- Opens the "Select Terminals" popover the way a stop row does (a check cannot click that button). The
-- stand-in recipe has the base recipe's name, so the mod's wrapper swaps it for the terminal usage buttons;
-- if the hook is missing, the stand-in renders and the check fails.
local popover_react_util = require("::/gui/main/popover_react_util.tl")
local line_util = require("::/gui/line_vehicle_mgmt/line_util.tl")

local FakeTerminalSelection = react.RegisterRecipe("TerminalSelection", function()
	return builtin.BoxLayout{ children = { builtin.TextView{ text = "base terminal selection (hook missing)" } } }
end)

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
			x = 700, y = 300,
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

function data()
	return probe
end

return probe
