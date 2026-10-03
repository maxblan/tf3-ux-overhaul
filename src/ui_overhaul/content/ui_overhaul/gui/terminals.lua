--- Line Manager, "Select Terminals" popover of a stop: each terminal has three toggle buttons
-- [Don't Use | Alternative | Preferred] instead of the drop-down list, so one click sets its usage
-- (base: open the list, then pick). The buttons of the preferred terminal stay disabled, as the base
-- list is. Everything else in the popover is the base popover; the problem arrow of a terminal is
-- also shown on the right terminal only (base compares terminal numbers modulo the stop count).
--
-- A Lua conversion of the base recipe TerminalSelection (gui/line_vehicle_mgmt/line_manager_panel.tl),
-- registered under the base name so the base stylesheet applies. The base recipe is file-local, so it
-- cannot be replaced: instead the exported module function popover_react_util.PopoverWindowContent,
-- which PopoverWindow looks up each time it renders, is wrapped; for the terminal popover only, the
-- wrapper hands it this recipe instead of the base one. Other mods that replace the recipe
-- PopoverWindowContent (e.g. Auto Assign Terminals) still see the same parameters. If rendering fails,
-- the base popover is shown. Installed by terminals.script.lua.
-- @module ui_overhaul.gui.terminals
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local line_react_util = require("::/gui/line_vehicle_mgmt/line_react_util.tl")
local line_util = require("::/gui/line_vehicle_mgmt/line_util.tl")
local popover_react_util = require("::/gui/main/popover_react_util.tl")
local react = require("::/gui/main/react.lua")
local styleutil = require("::/gui/main/styleutil.tl")

local terminals = {}

local BASE_NAME = "TerminalSelection"

-- Button order and values as in the base drop-down list.
local USAGES = { "Unused", "Alternative", "Main" }

-- The base recipe, taken from the first terminal popover; shown if this one fails.
local base_recipe

local reported = {}
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] terminal selection: ", key, ": ", tostring(err))
end

-- Terminals of the stop (base getter, unchanged except that the overlength check runs once per stop).
-- Engine reads only; runs every step.
local function read_terminals(params)
	local via = params.viaState:old()[params.stopNumber]
	local stationGroup = api.engine.getComponent(via.stop.stationGroup, api.type.ComponentType.STATION_GROUP)

	local stationTerminal2overlength = api.engine.system.transportVehicleSystem.checkLineStopForVehicleOverlength(
		params.lineEntity,
		params.stopIndex
	)

	local result = {}
	local terminalIndex = 1
	for stationIndex1, stationEntity in ipairs(stationGroup.stations) do
		local station = api.engine.getComponent(stationEntity, api.type.ComponentType.STATION)

		for terminalIndex1, terminal in ipairs(station.terminals) do
			local alternativeHere = false
			for _i, alternative in ipairs(via.stop.alternativeTerminals) do
				if alternative.station + 1 == stationIndex1 and alternative.terminal + 1 == terminalIndex1 then
					alternativeHere = true
				end
			end

			local terminalSpecialization
			for _i, transferSpeed in ipairs(terminal.cargoTransferSpeeds) do
				for _j, class in ipairs(transferSpeed.cargoTypeSet.cargoClassesIncluded) do
					terminalSpecialization = class
				end
			end
			local isPassengerTerminal = terminal.passengersLoad or terminal.passengersUnload
			local isCargoTerminal = terminal.cargoLoad or terminal.cargoUnload

			local terminalLength = line_util.getTerminalLength(stationEntity, terminalIndex1)

			local hasOverlength = false
			local stationIndex0 = stationIndex1 - 1
			local terminalIndex0 = terminalIndex1 - 1
			for stationTerminal, _v in pairs(stationTerminal2overlength) do
				if stationTerminal.station == stationIndex0 and stationTerminal.terminal == terminalIndex0 then
					hasOverlength = true
				end
			end

			table.insert(result, {
				number = terminalIndex,
				current = via.stop.station1 == stationIndex1 and via.stop.terminal1 == terminalIndex1,
				stationEntity = stationEntity,
				stationIndex1 = stationIndex1,
				terminalIndex1 = terminalIndex1,
				hasOverlength = hasOverlength,
				alternativeHere = alternativeHere,
				terminalSpecialization = terminalSpecialization,
				terminalLength = terminalLength,
				isPassengerTerminal = isPassengerTerminal,
				isCargoTerminal = isCargoTerminal,
			})
			terminalIndex = terminalIndex + 1
		end
	end
	return result
end

--- Usage of a terminal: "Main" (preferred), "Alternative" or "Unused".
function terminals.usage(terminalData)
	if terminalData.current then return "Main" end
	if terminalData.alternativeHere then return "Alternative" end
	return "Unused"
end

--- The one call that sets `usage` for a terminal currently used as `current`, as the base list does on
-- a change: Preferred -> changeMainTerminal, Alternative / Don't Use -> selectAlternativeTerminal.
-- Only one call per click: a second one in the same frame would start from the old line state and undo
-- the first. Nothing for the preferred terminal (the base list is disabled there) or an unchanged usage.
function terminals.apply(commonParams, stopNumber, terminalData, current, usage)
	if usage == nil or usage == current or current == "Main" then return false end
	if usage == "Main" then
		commonParams.changeMainTerminal(stopNumber, terminalData.stationIndex1, terminalData.terminalIndex1)
	else
		commonParams.selectAlternativeTerminal(stopNumber, terminalData.stationIndex1, terminalData.terminalIndex1,
			usage == "Alternative")
	end
	return true
end

-- [Don't Use | Alternative | Preferred], the current usage checked.
local function usage_buttons(params, terminalData)
	local current = terminals.usage(terminalData)
	local enabled = current ~= "Main"
	local labels = { _("Don't Use"), _("Alternative"), _("Preferred") }
	local buttons, selected = {}, 1
	for i, usage in ipairs(USAGES) do
		buttons[i] = {
			meta = { enabled = enabled },
			content = builtin.TextView{ meta = { class = "font-scale-annotation" }, text = labels[i] },
		}
		if usage == current then selected = i end
	end
	return builtin.ToggleButtonGroup{
		meta = {
			id = "uio.terminals.usage." .. tostring(terminalData.number),
			tooltip = _("Set Terminal Usage"),
			enabled = enabled,
		},
		buttons = buttons,
		selected = selected,
		onValueChange = function(index)
			terminals.apply(params.commonParams, params.stopNumber, terminalData, current, USAGES[index])
		end,
	}
end

local function render(params)
	if not params.viaState or not params.viaState:old() then
		return builtin.BoxLayout{}
	end

	local terminalsState = engine_react_util.useStepState(function(old)
		local ok, result = pcall(read_terminals, params)
		if ok then return result end
		report("read", result)
		return old or {}
	end)

	local selectTerminalsHeader = builtin.Component{
		meta = {
			class = "select-terminals-header",
		},
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.TextView{
					meta = {
						class = "font-scale-headline",
					},
					text = lang_util.format(_("Terminals for Stop {stopnumber}"), {
						stopnumber = lang_util.formatInt(params.stopNumber),
					}),
				},
			},
		},
	}

	local children = {}
	for terminalNumber, terminalData in ipairs(terminalsState:old()) do
		local terminalText = _("Passenger and Cargo")
		local bubbleColor
		if terminalData.isPassengerTerminal then
			if not terminalData.isCargoTerminal then
				terminalText = _("Passenger")
			end
		else
			if terminalData.terminalSpecialization ~= "UNIVERSAL" then
				local cargoClassId = api.res.cargoClassRep.getCargoClassId(terminalData.terminalSpecialization)
				if cargoClassId ~= -1 then
					local specializationData = api.res.cargoClassRep.get(cargoClassId)

					terminalText = specializationData.name
					bubbleColor = specializationData.color
				end
			else
				terminalText = _("All Cargo Types")
			end
		end

		local problemsPrev = params.index2problems[(params.stopNumber - 1) % params.stopCount]
		if not problemsPrev then
			problemsPrev = {}
		end
		local problemsThis = params.index2problems[params.stopNumber]
		if not problemsThis then
			problemsThis = {}
		end
		local problemPrev = false
		local problemThis = false
		local problemTooltipPrev = nil
		local problemTooltipThis = nil
		for _i, problem in ipairs(problemsPrev) do
			if params.stopNumber % params.stopCount == problem.stopAndTerminalNext.stop % params.stopCount then
				if terminalNumber == problem.stopAndTerminalNext.terminal then
					problemPrev = true
					problemTooltipPrev = problem.tooltip
				end
			end
		end
		for _i, problem in ipairs(problemsThis) do
			if params.stopNumber == problem.stopAndTerminalThis.stop then
				-- base: terminalNumber % stopCount == terminal % stopCount
				if terminalNumber == problem.stopAndTerminalThis.terminal then
					problemThis = true
					problemTooltipThis = problem.tooltip
				end
			end
		end

		local floatingChildren = {}

		table.insert(floatingChildren, builtin.FloatingLayoutChild{
			h = -1,
			v = -1,
			item = builtin.Component{
				meta = {
					class = "main, uio-terminal-row",
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						builtin.Component{
							meta = {
								class = "problem-spacer-terminal",
							},
						},
						line_react_util.makeTerminalIndicator(terminalData.number, true),
						builtin.TextView {
							meta = {
								tooltip = terminalText, -- this text gets clipped when too long, so show the tooltip always
								class = (bubbleColor and "bubble, " or "") .. "font-scale-body, terminal-label-compact",
								styleSheet = bubbleColor and styleutil.makeStyle{
									color = gui_react_util.textColorForColor(api.type.Vec4f.new(bubbleColor, 1.0)),
									backgroundColor1 = {
										bubbleColor.x,
										bubbleColor.y,
										bubbleColor.z,
										1.0
									},
								} or nil,
							},
							text = terminalText,
						},
						gui_react_util.makeHorizontalSpacer(),
						builtin.TextView{
							meta = {
								class = "font-scale-body, terminal-length, " ..
									(terminalData.terminalLength == 0 and "invisible" or ""),
							},
							text = api.util.formatLength(terminalData.terminalLength),
						},
						usage_buttons(params, terminalData),
					},
				},
			},
		})

		table.insert(floatingChildren, builtin.FloatingLayoutChild{
			h = 0,
			v = -1,
			item = builtin.Component{
				meta = {
					class = "problem-spacer-terminal",
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Vertical,
					children = {
						problemPrev and builtin.ImageView{
							meta = {
								class = "terminal-problem, top",
								tooltip = problemTooltipPrev,
							},
							path = params.commonParams.iconPaths.problemArrow,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						} or builtin.Component{
							meta = {
								class = "terminal-problem",
							},
						},
						problemThis and builtin.ImageView{
							meta = {
								class = "terminal-problem, bottom",
								tooltip = problemTooltipThis,
							},
							path = params.commonParams.iconPaths.problemArrow,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						} or builtin.Component{
							meta = {
								class = "terminal-problem",
							},
						},
					},
				},
			}
		})

		table.insert(floatingChildren, builtin.FloatingLayoutChild{
			h = 0,
			v = -1,
			item = builtin.Component{
				meta = {
					class = "problem-terminal-length",
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						terminalData.hasOverlength and builtin.ImageView{
							meta = {
								class = "terminal-length-alert",
								tooltip = _("Terminal is too short for some vehicles."),
							},
							path = params.commonParams.iconPaths.problemAlert,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						} or nil,
					},
				},
			}
		})

		table.insert(children, builtin.FloatingLayout{
			children = floatingChildren,
		})
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			selectTerminalsHeader,
			builtin.ScrollArea{
				horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
				verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
				content = builtin.Component{
					layout = builtin.BoxLayout{
						orientation = builtin.type.Orientation.Vertical,
						children = children,
					},
				},
			},
		},
	}
end

-- Recipe bodies run later than the call that creates their node, so the body guards itself.
local TerminalSelection = react.RegisterRecipe(BASE_NAME, function(params)
	local ok, node = pcall(render, params)
	if ok then return node end
	report("render (showing the base popover)", node)
	if base_recipe then return builtin.BoxLayout{ children = { base_recipe(params) } } end
	return builtin.BoxLayout{}
end)
terminals.TerminalSelection = TerminalSelection

--- Popover parameters with this recipe in place of the base terminal selection; other popovers' parameters
-- are returned unchanged. `recipe_name` is react.GetRecipeName (a parameter for the specs).
function terminals.swap(p, recipe_name)
	if type(p) ~= "table" or p.recipe == nil or p.recipe == TerminalSelection then return p end
	if recipe_name(p.recipe) ~= BASE_NAME then return p end
	base_recipe = p.recipe
	local copy = {}
	for k, v in pairs(p) do copy[k] = v end
	copy.recipe = TerminalSelection
	return copy
end

--- Wraps `previous` (the PopoverWindowContent function: the base recipe, or another mod's wrapper).
function terminals.wrap(previous)
	return function(p, ...)
		local ok, swapped = pcall(terminals.swap, p, react.GetRecipeName)
		if not ok then
			report("swap", swapped)
			swapped = p
		end
		return previous(swapped, ...)
	end
end

--- Called from the react-replacement-config before the UI starts.
function terminals.install(_replacement_api)
	local previous = popover_react_util.PopoverWindowContent
	if previous == nil then error("popover_react_util.PopoverWindowContent not found") end
	popover_react_util.PopoverWindowContent = terminals.wrap(previous)
	debugPrint("[ui_overhaul] terminal usage buttons installed")
end

return terminals
